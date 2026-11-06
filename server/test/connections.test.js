import assert from 'node:assert/strict'
import { mkdtempSync, rmSync } from 'node:fs'
import { createServer } from 'node:http'
import { tmpdir } from 'node:os'
import path from 'node:path'
import test from 'node:test'
import { createApp } from '../src/app.js'
import { openDatabase } from '../src/db.js'

test('records client ip, location, and device', async (t) => {
  const dir = mkdtempSync(path.join(tmpdir(), 'hajimi-'))
  const db = openDatabase(path.join(dir, 'app.sqlite'))
  const app = createApp({ db, config: {} })
  const server = createServer((req, res) => { app(req, res) })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  const base = `http://127.0.0.1:${server.address().port}`
  t.after(() => new Promise((resolve) => server.close(() => {
    db.close()
    rmSync(dir, { recursive: true, force: true })
    resolve()
  })))

  const headers = {
    'x-forwarded-for': '203.0.113.7, 10.0.0.1',
    'x-vercel-ip-city': 'San%20Francisco',
    'x-vercel-ip-country': 'US',
    'x-vercel-ip-country-region': 'CA',
    'x-client-id': 'device-1',
    'x-device-model': 'iPhone16,1',
    'x-os-version': 'iOS 26.1',
  }
  await fetch(`${base}/health`, { headers })
  await fetch(`${base}/me`, { headers: { ...headers, 'x-vercel-ip-city': '' } })

  const row = db.db.prepare('SELECT * FROM client_connections WHERE client_id = ?').get('device-1')
  assert.equal(row.ip, '203.0.113.7')
  assert.equal(row.city, 'San Francisco')
  assert.equal(row.country, 'US')
  assert.equal(row.device_model, 'iPhone16,1')
  assert.equal(row.request_count, 2)
  assert.equal(row.last_path, '/me')
})
