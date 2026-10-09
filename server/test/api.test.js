import assert from 'node:assert/strict'
import { mkdtempSync, rmSync } from 'node:fs'
import { createServer } from 'node:http'
import { tmpdir } from 'node:os'
import path from 'node:path'
import test from 'node:test'
import { createApp } from '../src/app.js'
import { openDatabase } from '../src/db.js'

function testConfig() {
  return {
    googleClientId: 'test-client',
    llmApiKey: '',
    llmBaseURL: 'https://example.invalid/v1',
    llmModel: 'test-model',
    systemPrompt: 'test',
  }
}

async function listen(server) {
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  const address = server.address()
  assert(address && typeof address === 'object')
  return address.port
}

test('auth, sessions, and missing model key', async (t) => {
  const dir = mkdtempSync(path.join(tmpdir(), 'hajimi-'))
  const db = openDatabase(path.join(dir, 'app.sqlite'))
  const app = createApp({ db, config: testConfig() })
  const server = createServer((req, res) => {
    app(req, res)
  })
  const port = await listen(server)
  const base = `http://127.0.0.1:${port}`

  t.after(() => new Promise((resolve, reject) => {
    server.close((error) => {
      db.close()
      rmSync(dir, { recursive: true, force: true })
      if (error) reject(error)
      else resolve()
    })
  }))

  const health = await fetch(`${base}/health`)
  assert.equal(health.status, 200)

  const denied = await fetch(`${base}/sessions`)
  assert.equal(denied.status, 401)

  const user = db.upsertGoogleUser({
    sub: 'sub-1',
    email: 'a@example.com',
    name: 'Ada',
    picture: null,
  })
  const token = db.createToken(user.id)
  const headers = {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  }

  const created = await fetch(`${base}/sessions`, {
    method: 'POST',
    headers,
    body: '{}',
  })
  assert.equal(created.status, 201)
  const session = await created.json()
  assert.equal(session.title, '新对话')

  const sent = await fetch(`${base}/sessions/${session.id}/messages`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ content: '你好' }),
  })
  assert.equal(sent.status, 503)
  const sentBody = await sent.json()
  assert.match(sentBody.error, /LLM_API_KEY/)

  const listed = await fetch(`${base}/sessions/${session.id}/messages`, { headers })
  assert.equal(listed.status, 200)
  assert.deepEqual((await listed.json()).messages, [])

  const other = db.upsertGoogleUser({
    sub: 'sub-2',
    email: 'b@example.com',
    name: 'Bea',
    picture: null,
  })
  const otherToken = db.createToken(other.id)
  const forbidden = await fetch(`${base}/sessions/${session.id}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${otherToken}` },
  })
  assert.equal(forbidden.status, 404)

  const removed = await fetch(`${base}/sessions/${session.id}`, {
    method: 'DELETE',
    headers,
  })
  assert.equal(removed.status, 200)
  const missing = await fetch(`${base}/sessions/${session.id}/messages`, { headers })
  assert.equal(missing.status, 404)
})

test('session titles stay with the owner and messages cascade', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'hajimi-'))
  const db = openDatabase(path.join(dir, 'app.sqlite'))
  try {
    const user = db.upsertGoogleUser({
      sub: 'sub-1',
      email: 'a@example.com',
      name: 'Ada',
      picture: null,
    })
    const other = db.upsertGoogleUser({
      sub: 'sub-2',
      email: 'b@example.com',
      name: 'Bea',
      picture: null,
    })
    const session = db.createSession(user.id)
    db.addMessage(session.id, 'user', '  今天   天气怎么样  ')
    assert.equal(db.getSession(user.id, session.id).title, '今天 天气怎么样')
    db.addMessage(session.id, 'user', '第二条')
    assert.equal(db.getSession(user.id, session.id).title, '今天 天气怎么样')
    assert.equal(db.getSession(other.id, session.id), null)

    const longSession = db.createSession(user.id)
    db.addMessage(longSession.id, 'user', 'a'.repeat(30))
    assert.equal(db.getSession(user.id, longSession.id).title, `${'a'.repeat(24)}…`)

    assert.equal(db.deleteSession(user.id, session.id), true)
    assert.equal(db.messageCount(session.id), 0)
    assert.equal(db.listMessages(user.id, session.id), null)
  } finally {
    db.close()
    rmSync(dir, { recursive: true, force: true })
  }
})
