import { createHash, randomBytes, randomUUID } from 'node:crypto'
import pg from 'pg'

const { Pool } = pg

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

const schema = `
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  google_sub TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL,
  name TEXT NOT NULL,
  picture TEXT,
  created_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  title TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS auth_tokens (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, created_at ASC);
`

class PostgresRepository {
  constructor(connectionString) {
    this.pool = new Pool({
      connectionString,
      max: 5,
      idleTimeoutMillis: 20_000,
      connectionTimeoutMillis: 10_000,
    })
    this.initialized = this.pool.query(schema)
  }

  async ready() {
    await this.initialized
  }

  async close() {
    await this.pool.end()
  }

  async userById(id, queryable = this.pool) {
    await this.ready()
    const { rows } = await queryable.query(
      'SELECT id, email, name, picture FROM users WHERE id = $1',
      [id],
    )
    return rows[0] ?? null
  }

  async upsertGoogleUser(profile) {
    await this.ready()
    const id = randomUUID()
    const { rows } = await this.pool.query(
      `INSERT INTO users (id, google_sub, email, name, picture, created_at)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (google_sub) DO UPDATE
       SET email = EXCLUDED.email, name = EXCLUDED.name, picture = EXCLUDED.picture
       RETURNING id, email, name, picture`,
      [id, profile.sub, profile.email, profile.name, profile.picture, new Date()],
    )
    return rows[0]
  }

  async createToken(userId) {
    await this.ready()
    const token = randomBytes(32).toString('base64url')
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
    await this.pool.query(
      'INSERT INTO auth_tokens (token_hash, user_id, expires_at) VALUES ($1, $2, $3)',
      [tokenHash(token), userId, expiresAt],
    )
    return token
  }

  async deleteToken(token) {
    await this.ready()
    await this.pool.query('DELETE FROM auth_tokens WHERE token_hash = $1', [tokenHash(token)])
  }

  async userForToken(token) {
    await this.ready()
    const { rows } = await this.pool.query(
      `SELECT users.id, users.email, users.name, users.picture
       FROM auth_tokens
       JOIN users ON users.id = auth_tokens.user_id
       WHERE auth_tokens.token_hash = $1 AND auth_tokens.expires_at > NOW()`,
      [tokenHash(token)],
    )
    return rows[0] ?? null
  }

  async listSessions(userId) {
    await this.ready()
    const { rows } = await this.pool.query(
      `SELECT id, title, created_at, updated_at
       FROM sessions
       WHERE user_id = $1
       ORDER BY updated_at DESC`,
      [userId],
    )
    return rows.map(mapSession)
  }

  async createSession(userId) {
    await this.ready()
    const id = randomUUID()
    const now = new Date()
    const { rows } = await this.pool.query(
      `INSERT INTO sessions (id, user_id, title, created_at, updated_at)
       VALUES ($1, $2, 'New chat', $3, $3)
       RETURNING id, title, created_at, updated_at`,
      [id, userId, now],
    )
    return mapSession(rows[0])
  }

  async getSession(userId, sessionId, queryable = this.pool) {
    await this.ready()
    const { rows } = await queryable.query(
      `SELECT id, title, created_at, updated_at
       FROM sessions
       WHERE id = $1 AND user_id = $2`,
      [sessionId, userId],
    )
    return rows[0] ? mapSession(rows[0]) : null
  }

  async deleteSession(userId, sessionId) {
    await this.ready()
    const result = await this.pool.query(
      'DELETE FROM sessions WHERE id = $1 AND user_id = $2',
      [sessionId, userId],
    )
    return result.rowCount > 0
  }

  async listMessages(userId, sessionId) {
    await this.ready()
    if (!await this.getSession(userId, sessionId)) return null
    const { rows } = await this.pool.query(
      `SELECT id, role, content, created_at
       FROM messages
       WHERE session_id = $1
       ORDER BY created_at ASC, id ASC`,
      [sessionId],
    )
    return rows.map(mapMessage)
  }

  async messageCount(sessionId) {
    await this.ready()
    const { rows } = await this.pool.query(
      'SELECT COUNT(*)::integer AS n FROM messages WHERE session_id = $1',
      [sessionId],
    )
    return Number(rows[0].n)
  }

  async addMessage(sessionId, role, content) {
    await this.ready()
    const client = await this.pool.connect()
    try {
      await client.query('BEGIN')
      const id = randomUUID()
      const now = new Date()
      const inserted = await client.query(
        `INSERT INTO messages (id, session_id, role, content, created_at)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, role, content, created_at`,
        [id, sessionId, role, content, now],
      )

      if (role === 'user') {
        await client.query(
          `UPDATE sessions
           SET title = CASE WHEN title = 'New chat' THEN $1 ELSE title END, updated_at = $2
           WHERE id = $3`,
          [titleFrom(content), now, sessionId],
        )
      } else {
        await client.query('UPDATE sessions SET updated_at = $1 WHERE id = $2', [now, sessionId])
      }
      await client.query('COMMIT')
      return mapMessage(inserted.rows[0])
    } catch (error) {
      await client.query('ROLLBACK')
      throw error
    } finally {
      client.release()
    }
  }
}

export function openPostgresDatabase(connectionString) {
  if (!connectionString) throw new Error('DATABASE_URL is not set')
  return new PostgresRepository(connectionString)
}
