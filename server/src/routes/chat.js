import { HttpError } from '../errors.js'
import { openChatCompletion, readChatStream } from '../llm.js'

function modelMessages(history, content) {
  return history.slice(-39).map((message) => ({
    role: message.role,
    content: message.content,
  })).concat({ role: 'user', content })
}

export function registerChatRoutes(router) {
  router.post('/sessions/:id/messages', async (ctx) => {
    const user = ctx.requireUser()
    const session = ctx.deps.db.getSession(user.id, ctx.params.id)
    if (!session) throw new HttpError(404, '对话不存在')

    const body = await ctx.readJSON()
    const content = typeof body.content === 'string' ? body.content.trim() : ''
    if (!content) throw new HttpError(400, '消息不能为空')
    if (Array.from(content).length > 32000) throw new HttpError(400, '消息太长')

    const history = ctx.deps.db.listMessages(user.id, session.id) ?? []
    const abort = new AbortController()
    const timeout = AbortSignal.timeout(180_000)
    const signal = AbortSignal.any([abort.signal, timeout])
    const stopOnDisconnect = () => {
      if (!ctx.res.writableEnded) abort.abort()
    }
    ctx.req.on('aborted', () => abort.abort())
    ctx.res.on('close', stopOnDisconnect)

    let response
    try {
      response = await openChatCompletion({
        config: ctx.deps.config,
        messages: modelMessages(history, content),
        signal,
      })
    } catch (error) {
      if (error instanceof HttpError) throw error
      if (timeout.aborted) throw new HttpError(504, '模型响应超时')
      if (abort.signal.aborted) return
      throw new HttpError(502, '连不上模型接口')
    }

    const userMessage = ctx.deps.db.addMessage(session.id, 'user', content)
    const sessionAfterUser = ctx.deps.db.getSession(user.id, session.id)

    ctx.res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
    })
    const send = (event) => {
      if (!ctx.res.writableEnded) {
        ctx.res.write(`data: ${JSON.stringify(event)}\n\n`)
      }
    }

    send({ type: 'user', message: userMessage, session: sessionAfterUser })

    let full = ''
    let failed = null
    try {
      await readChatStream(response.body, {
        signal,
        onDelta(delta) {
          full += delta
          send({ type: 'delta', text: delta })
        },
      })
    } catch (error) {
      if (!abort.signal.aborted) {
        failed = error
      }
    }

    if (full.trim()) {
      const assistant = ctx.deps.db.addMessage(session.id, 'assistant', full)
      send({
        type: 'done',
        message: assistant,
        session: ctx.deps.db.getSession(user.id, session.id),
      })
    }

    if (failed) {
      send({ type: 'error', error: failed.message || '生成中断' })
    } else if (!full.trim() && !abort.signal.aborted) {
      send({ type: 'error', error: '模型没有返回内容' })
    }

    if (!ctx.res.writableEnded) ctx.res.end()
  })
}
