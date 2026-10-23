import { createApp } from '../src/app.js'
import { loadConfig } from '../src/config.js'
import { openPostgresDatabase } from '../src/postgres-db.js'
import { sendJSON } from '../src/router.js'

let appPromise

async function loadApp() {
  if (!appPromise) {
    appPromise = (async () => {
      const databaseURL = process.env.DATABASE_URL || process.env.POSTGRES_URL
      const db = openPostgresDatabase(databaseURL)
      await db.ready()
      return createApp({ db, config: loadConfig() })
    })()
  }
  return appPromise
}

export default async function handler(req, res) {
  try {
    const app = await loadApp()
    await app(req, res)
  } catch (error) {
    console.error(error)
    if (!res.headersSent && !res.writableEnded) {
      sendJSON(res, 500, { error: 'Server configuration failed' })
    } else if (!res.writableEnded) {
      res.end()
    }
  }
}
