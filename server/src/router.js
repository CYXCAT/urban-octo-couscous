import { HttpError } from './errors.js'

function compile(path) {
  const names = []
  const source = path.split('/').map((part) => {
    if (part.startsWith(':')) {
      names.push(part.slice(1))
      return '([^/]+)'
    }
    return part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  }).join('/')
  return { names, regex: new RegExp(`^${source}$`) }
}

export function sendJSON(res, status, body) {
  const payload = JSON.stringify(body)
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
  })
  res.end(payload)
}

class Context {
  constructor({ req, res, params, deps }) {
    this.req = req
    this.res = res
    this.params = params
    this.deps = deps
  }

  json(status, body) {
    sendJSON(this.res, status, body)
  }

  async readJSON() {
    const chunks = []
    let size = 0
    for await (const chunk of this.req) {
      size += chunk.length
      if (size > 1_000_000) throw new HttpError(413, 'Request body is too large')
      chunks.push(chunk)
    }
    if (size === 0) return {}
    try {
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'))
      if (!body || typeof body !== 'object' || Array.isArray(body)) {
        throw new HttpError(400, 'Request body must be a JSON object')
      }
      return body
    } catch (error) {
      if (error instanceof HttpError) throw error
      throw new HttpError(400, 'Request body is not JSON')
    }
  }

  async requireUser() {
    const header = this.req.headers.authorization || ''
    const match = /^Bearer\s+(\S+)$/.exec(header)
    if (!match) throw new HttpError(401, 'Not signed in')
    const user = await this.deps.db.userForToken(match[1])
    if (!user) throw new HttpError(401, 'Session expired')
    return user
  }
}

export function createRouter(deps) {
  const routes = []

  function add(method, path, handler) {
    routes.push({ method, ...compile(path), handler })
  }

  return {
    get(path, handler) { add('GET', path, handler) },
    post(path, handler) { add('POST', path, handler) },
    delete(path, handler) { add('DELETE', path, handler) },
    async handle(req, res) {
      let url
      try {
        url = new URL(req.url || '/', 'http://127.0.0.1')
      } catch {
        throw new HttpError(400, 'Invalid request URL')
      }
      const pathname = url.pathname.replace(/\/$/, '') || '/'
      const route = routes.find((item) => item.method === req.method && item.regex.test(pathname))
      if (!route) throw new HttpError(404, 'Not found')
      const match = route.regex.exec(pathname)
      const params = {}
      route.names.forEach((name, index) => {
        params[name] = match[index + 1]
      })
      const ctx = new Context({ req, res, params, deps })
      await route.handler(ctx)
    },
  }
}
