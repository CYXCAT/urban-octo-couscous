import { createServer } from 'node:http'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createApp } from './app.js'
import { loadConfig } from './config.js'
import { openDatabase } from './db.js'
import { lanIPv4, publishService } from './discovery.js'

const serverRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const config = loadConfig()
const db = openDatabase(path.join(serverRoot, 'data', 'hajimi.sqlite'))
const app = createApp({ db, config })
const server = createServer((req, res) => {
  app(req, res)
})

server.requestTimeout = 0
server.headersTimeout = 60_000

let stopDiscovery = () => {}

server.on('error', (error) => {
  stopDiscovery()
  if (error.code === 'EADDRINUSE') {
    console.error(`Port ${config.port} is already in use`)
  } else {
    console.error(error)
  }
  process.exit(1)
})

function shutdown() {
  stopDiscovery()
  server.close(() => {
    db.close()
    process.exit(0)
  })
}

process.on('SIGINT', shutdown)
process.on('SIGTERM', shutdown)

server.listen(config.port, config.host, () => {
  console.log('hajimi server is running')
  console.log(`  local  http://127.0.0.1:${config.port}`)
  for (const address of lanIPv4()) {
    console.log(`  lan    http://${address}:${config.port}`)
  }
  if (!config.llmApiKey) {
    console.log('LLM_API_KEY is not set. Sign-in and sessions work, but sending messages will fail.')
  }
  stopDiscovery = publishService(config.port)
})
