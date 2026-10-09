import { HttpError } from './errors.js'

export function chatCompletionsURL(baseURL) {
  return `${baseURL.replace(/\/$/, '')}/chat/completions`
}

export function consumeSSEBuffer(buffer, { flush = false } = {}) {
  const lines = buffer.split('\n')
  const rest = flush ? '' : (lines.pop() ?? '')
  const deltas = []
  let done = false
  let error = null

  for (const raw of lines) {
    const line = raw.replace(/\r$/, '').trim()
    if (!line.startsWith('data:')) continue
    const data = line.slice(5).trim()
    if (!data) continue
    if (data === '[DONE]') {
      done = true
      continue
    }

    let json
    try {
      json = JSON.parse(data)
    } catch {
      continue
    }

    if (json.error) {
      error = typeof json.error === 'string'
        ? json.error
        : (json.error.message || 'Model request failed')
      break
    }

    const text = json.choices?.[0]?.delta?.content
    if (typeof text === 'string' && text.length > 0) deltas.push(text)
  }

  return { deltas, done, rest, error }
}

async function readErrorMessage(response) {
  const text = await response.text()
  try {
    const json = JSON.parse(text)
    if (typeof json.error === 'string') return json.error
    if (json.error?.message) return json.error.message
  } catch {
    // Keep the raw text.
  }
  const compact = text.replace(/\s+/g, ' ').trim()
  if (!compact) return `Model request failed (${response.status})`
  return compact.slice(0, 300)
}

export async function openChatCompletion({ config, messages, signal }) {
  if (!config.llmApiKey) {
    throw new HttpError(503, 'LLM_API_KEY is not set. Add it to server/.env and restart the server.')
  }

  let response
  try {
    response = await fetch(chatCompletionsURL(config.llmBaseURL), {
      method: 'POST',
      signal,
      headers: {
        Authorization: `Bearer ${config.llmApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: config.llmModel,
        stream: true,
        messages: [
          { role: 'system', content: config.systemPrompt },
          ...messages,
        ],
      }),
    })
  } catch (error) {
    if (signal?.aborted) throw error
    throw new HttpError(502, 'Could not reach the model API')
  }

  if (!response.ok) {
    throw new HttpError(502, await readErrorMessage(response))
  }
  if (!response.body) throw new HttpError(502, 'The model returned no data')
  return response
}

export async function readChatStream(body, { onDelta, signal }) {
  const reader = body.getReader()
  const decoder = new TextDecoder()
  let rest = ''

  const apply = (parsed) => {
    for (const delta of parsed.deltas) onDelta(delta)
    if (parsed.error) throw new Error(parsed.error)
    return parsed.done
  }

  try {
    while (true) {
      if (signal?.aborted) return
      const { done, value } = await reader.read()
      if (done) {
        rest += decoder.decode()
        apply(consumeSSEBuffer(rest, { flush: true }))
        return
      }
      rest += decoder.decode(value, { stream: true })
      const parsed = consumeSSEBuffer(rest)
      rest = parsed.rest
      if (apply(parsed)) return
    }
  } catch (error) {
    if (signal?.aborted) return
    throw error
  } finally {
    reader.releaseLock()
  }
}
