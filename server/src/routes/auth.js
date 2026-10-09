import { HttpError } from '../errors.js'
import { verifyGoogleIDToken } from '../google.js'

export function registerAuthRoutes(router) {
  router.get('/health', async (ctx) => {
    ctx.json(200, { ok: true, service: 'hajimi' })
  })

  router.post('/auth/google', async (ctx) => {
    const body = await ctx.readJSON()
    const idToken = typeof body.idToken === 'string' ? body.idToken.trim() : ''
    if (!idToken) throw new HttpError(400, 'Missing Google ID token')
    const profile = await verifyGoogleIDToken(idToken, ctx.deps.config.googleClientId)
    const user = ctx.deps.db.upsertGoogleUser(profile)
    const token = ctx.deps.db.createToken(user.id)
    ctx.json(200, { token, user })
  })

  router.post('/auth/logout', async (ctx) => {
    const header = ctx.req.headers.authorization || ''
    const match = /^Bearer\s+(\S+)$/.exec(header)
    if (match) ctx.deps.db.deleteToken(match[1])
    ctx.json(200, { ok: true })
  })

  router.get('/me', async (ctx) => {
    ctx.json(200, { user: ctx.requireUser() })
  })
}
