import assert from 'node:assert/strict'
import test from 'node:test'
import { consumeSSEBuffer } from '../src/llm.js'

test('parses SSE deltas split across chunks', () => {
  const first = consumeSSEBuffer('data: {"choices":[{"delta":{"content":"Hi"}}]}\n\ndata: {"cho')
  assert.deepEqual(first.deltas, ['Hi'])
  assert.equal(first.done, false)

  const second = consumeSSEBuffer(`${first.rest}ices":[{"delta":{"content":"!"}}]}\n\ndata: [DONE]\n`)
  assert.deepEqual(second.deltas, ['!'])
  assert.equal(second.done, true)
})

test('reads an error payload from the model stream', () => {
  const parsed = consumeSSEBuffer('data: {"error":{"message":"bad key"}}\n', { flush: true })
  assert.equal(parsed.error, 'bad key')
  assert.deepEqual(parsed.deltas, [])
})
