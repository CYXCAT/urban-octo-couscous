import { recordConnection } from './connections.js'
import { HttpError } from './errors.js'
import { registerRoutes } from './routes/register.js'
import { createRouter, sendJSON } from './router.js'

export function createApp(deps) {
  const router = createRouter(deps)
  registerRoutes(router)

  return async (req, res) => {
    try {
      await recordConnection(deps.db, req)
      await router.handle(req, res)
    } catch (error) {
      if (res.headersSent || res.writableEnded) {
        if (!res.writableEnded) res.end()
        return
      }
      const status = error instanceof HttpError ? error.status : 500
      const message = error instanceof HttpError ? error.message : 'Internal server error'
      if (!(error instanceof HttpError)) console.error(error)
      sendJSON(res, status, { error: message })
    }
  }
}
