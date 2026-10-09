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
      if (size > 1_000_000) throw new HttpError(413, '请求体过大')
      chunks.push(chunk)
    }
    if (size === 0) return {}
    try {
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'))
      if (!body || typeof body !== 'object' || Array.isArray(body)) {
        throw new HttpError(400, '请求体不是 JSON 对象')
      }
      return body
    } catch (error) {
      if (error instanceof HttpError) throw error
      throw new HttpError(400, '请求体不是 JSON')
    }
  }

  requireUser() {
    const header = this.req.headers.authorization || ''
    const match = /^Bearer\s+(\S+)$/.exec(header)
    if (!match) throw new HttpError(401, '未登录')
    const user = this.deps.db.userForToken(match[1])
    if (!user) throw new HttpError(401, '登录已过期')
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
        throw new HttpError(400, '请求地址无效')
      }
      const pathname = url.pathname.replace(/\/$/, '') || '/'
      const route = routes.find((item) => item.method === req.method && item.regex.test(pathname))
      if (!route) throw new HttpError(404, '不存在')
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
