import { createHash, randomBytes, randomUUID } from 'node:crypto'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { DatabaseSync } from 'node:sqlite'

function tokenHash(token) {
  return createHash('sha256').update(token).digest('hex')
}

function titleFrom(text) {
  const compact = text.replace(/\s+/g, ' ').trim()
  if (!compact) return 'New chat'
  const chars = Array.from(compact)
  if (chars.length <= 24) return compact
  return `${chars.slice(0, 24).join('')}…`
}

function mapSession(row) {
  return {
    id: row.id,
    title: row.title,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

function mapMessage(row) {
  return {
    id: row.id,
    role: row.role,
    content: row.content,
    createdAt: row.created_at,
  }
}

class Repository {
  constructor(db) {
    this.db = db
  }

  close() {
    this.db.close()
  }

  userById(id) {
    const row = this.db.prepare(
      'SELECT id, email, name, picture FROM users WHERE id = ?',
    ).get(id)
    if (!row) return null
    return {
      id: row.id,
      email: row.email,
      name: row.name,
      picture: row.picture,
    }
  }

  upsertGoogleUser(profile) {
    const existing = this.db.prepare(
      'SELECT id FROM users WHERE google_sub = ?',
    ).get(profile.sub)

    if (existing) {
      this.db.prepare(
        'UPDATE users SET email = ?, name = ?, picture = ? WHERE id = ?',
      ).run(profile.email, profile.name, profile.picture, existing.id)
      return this.userById(existing.id)
    }

    const id = randomUUID()
    this.db.prepare(
      `INSERT INTO users (id, google_sub, email, name, picture, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    ).run(id, profile.sub, profile.email, profile.name, profile.picture, new Date().toISOString())
    return this.userById(id)
  }

  createToken(userId) {
    const token = randomBytes(32).toString('base64url')
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
    this.db.prepare(
      'INSERT INTO auth_tokens (token_hash, user_id, expires_at) VALUES (?, ?, ?)',
    ).run(tokenHash(token), userId, expiresAt)
    return token
  }

  deleteToken(token) {
    this.db.prepare('DELETE FROM auth_tokens WHERE token_hash = ?').run(tokenHash(token))
  }

  userForToken(token) {
    const hash = tokenHash(token)
    const row = this.db.prepare(
      'SELECT user_id, expires_at FROM auth_tokens WHERE token_hash = ?',
    ).get(hash)
    if (!row) return null
    if (new Date(row.expires_at).getTime() <= Date.now()) {
      this.db.prepare('DELETE FROM auth_tokens WHERE token_hash = ?').run(hash)
      return null
    }
    return this.userById(row.user_id)
  }

  listSessions(userId) {
    return this.db.prepare(
      `SELECT id, title, created_at, updated_at
       FROM sessions
       WHERE user_id = ?
       ORDER BY updated_at DESC`,
    ).all(userId).map(mapSession)
  }

  createSession(userId) {
    const id = randomUUID()
    const now = new Date().toISOString()
    this.db.prepare(
      `INSERT INTO sessions (id, user_id, title, created_at, updated_at)
       VALUES (?, ?, 'New chat', ?, ?)`,
    ).run(id, userId, now, now)
    return this.getSession(userId, id)
  }

  getSession(userId, sessionId) {
    const row = this.db.prepare(
      `SELECT id, title, created_at, updated_at
       FROM sessions
       WHERE id = ? AND user_id = ?`,
    ).get(sessionId, userId)
    return row ? mapSession(row) : null
  }

  deleteSession(userId, sessionId) {
    const result = this.db.prepare(
      'DELETE FROM sessions WHERE id = ? AND user_id = ?',
    ).run(sessionId, userId)
    return result.changes > 0
  }

  listMessages(userId, sessionId) {
    if (!this.getSession(userId, sessionId)) return null
    return this.db.prepare(
      `SELECT id, role, content, created_at
       FROM messages
       WHERE session_id = ?
       ORDER BY created_at ASC, rowid ASC`,
    ).all(sessionId).map(mapMessage)
  }

  messageCount(sessionId) {
    const row = this.db.prepare(
      'SELECT COUNT(*) AS n FROM messages WHERE session_id = ?',
    ).get(sessionId)
    return Number(row.n)
  }

  addMessage(sessionId, role, content) {
    const id = randomUUID()
    const now = new Date().toISOString()
    this.db.exec('BEGIN')
    try {
      this.db.prepare(
        `INSERT INTO messages (id, session_id, role, content, created_at)
         VALUES (?, ?, ?, ?, ?)`,
      ).run(id, sessionId, role, content, now)

      if (role === 'user') {
        const current = this.db.prepare(
          'SELECT title FROM sessions WHERE id = ?',
        ).get(sessionId)
        const title = current?.title === 'New chat' ? titleFrom(content) : (current?.title ?? 'New chat')
        this.db.prepare(
          'UPDATE sessions SET title = ?, updated_at = ? WHERE id = ?',
        ).run(title, now, sessionId)
      } else {
        this.db.prepare(
          'UPDATE sessions SET updated_at = ? WHERE id = ?',
        ).run(now, sessionId)
      }
      this.db.exec('COMMIT')
    } catch (error) {
      this.db.exec('ROLLBACK')
      throw error
    }
    return { id, role, content, createdAt: now }
  }
}

const schema = `
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  google_sub TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL,
  name TEXT NOT NULL,
  picture TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS auth_tokens (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  expires_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, created_at ASC);
`

export function openDatabase(filePath) {
  mkdirSync(path.dirname(filePath), { recursive: true })
  const db = new DatabaseSync(filePath)
  db.exec(schema)
  return new Repository(db)
}
