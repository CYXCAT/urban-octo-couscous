import { copyFileSync, existsSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const envFile = path.join(root, '.env')

if (!existsSync(envFile)) {
  copyFileSync(path.join(root, '.env.example'), envFile)
}
