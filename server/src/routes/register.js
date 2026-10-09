import { registerAuthRoutes } from './auth.js'
import { registerChatRoutes } from './chat.js'
import { registerSessionRoutes } from './sessions.js'

export function registerRoutes(router) {
  registerAuthRoutes(router)
  registerSessionRoutes(router)
  registerChatRoutes(router)
}
