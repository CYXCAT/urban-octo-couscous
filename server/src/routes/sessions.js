import { HttpError } from '../errors.js'

export function registerSessionRoutes(router) {
  router.get('/sessions', async (ctx) => {
    const user = ctx.requireUser()
    ctx.json(200, { sessions: ctx.deps.db.listSessions(user.id) })
  })

  router.post('/sessions', async (ctx) => {
    const user = ctx.requireUser()
    await ctx.readJSON()
    ctx.json(201, ctx.deps.db.createSession(user.id))
  })

  router.delete('/sessions/:id', async (ctx) => {
    const user = ctx.requireUser()
    const deleted = ctx.deps.db.deleteSession(user.id, ctx.params.id)
    if (!deleted) throw new HttpError(404, 'Conversation not found')
    ctx.json(200, { ok: true })
  })

  router.get('/sessions/:id/messages', async (ctx) => {
    const user = ctx.requireUser()
    const messages = ctx.deps.db.listMessages(user.id, ctx.params.id)
    if (!messages) throw new HttpError(404, 'Conversation not found')
    ctx.json(200, { messages })
  })
}
