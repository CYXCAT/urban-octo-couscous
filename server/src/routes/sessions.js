import { HttpError } from '../errors.js'

export function registerSessionRoutes(router) {
  router.get('/sessions', async (ctx) => {
    const user = await ctx.requireUser()
    ctx.json(200, { sessions: await ctx.deps.db.listSessions(user.id) })
  })

  router.post('/sessions', async (ctx) => {
    const user = await ctx.requireUser()
    await ctx.readJSON()
    ctx.json(201, await ctx.deps.db.createSession(user.id))
  })

  router.delete('/sessions/:id', async (ctx) => {
    const user = await ctx.requireUser()
    const deleted = await ctx.deps.db.deleteSession(user.id, ctx.params.id)
    if (!deleted) throw new HttpError(404, 'Conversation not found')
    ctx.json(200, { ok: true })
  })

  router.get('/sessions/:id/messages', async (ctx) => {
    const user = await ctx.requireUser()
    const messages = await ctx.deps.db.listMessages(user.id, ctx.params.id)
    if (!messages) throw new HttpError(404, 'Conversation not found')
    ctx.json(200, { messages })
  })
}
