import { spawn } from 'node:child_process'
import os from 'node:os'

export function lanIPv4() {
  const addresses = []
  for (const entries of Object.values(os.networkInterfaces())) {
    for (const entry of entries ?? []) {
      const family = entry.family
      if ((family === 'IPv4' || family === 4) && !entry.internal) {
        addresses.push(entry.address)
      }
    }
  }
  return addresses
}

export function publishService(port) {
  const child = spawn('dns-sd', ['-R', 'hajimi', '_hajimi._tcp', 'local', String(port)], {
    stdio: ['ignore', 'pipe', 'pipe'],
  })

  const log = (chunk) => {
    const text = chunk.toString().trim()
    if (text) console.log(`[bonjour] ${text}`)
  }
  child.stdout?.on('data', log)
  child.stderr?.on('data', log)
  child.on('error', (error) => {
    console.error(`[bonjour] 无法发布本机服务：${error.message}`)
  })

  return () => {
    if (!child.killed) child.kill('SIGTERM')
  }
}
