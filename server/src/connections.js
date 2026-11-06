import { createHash } from 'node:crypto'

function header(req, name, maxLength = 200) {
  const value = req.headers[name]
  const text = Array.isArray(value) ? value[0] : value
  if (typeof text !== 'string') return null
  const trimmed = text.trim()
  return trimmed ? trimmed.slice(0, maxLength) : null
}

function decoded(value) {
  if (!value) return null
  try {
    return decodeURIComponent(value)
  } catch {
    return value
  }
}

function numberOrNull(value) {
  if (!value) return null
  const n = Number(value)
  return Number.isFinite(n) ? n : null
}

export function clientIP(req) {
  const forwarded = header(req, 'x-forwarded-for', 500)
  if (forwarded) return forwarded.split(',')[0].trim()
  const real = header(req, 'x-real-ip')
  if (real) return real
  const remote = req.socket?.remoteAddress || null
  return remote?.startsWith('::ffff:') ? remote.slice(7) : remote
}

// Collects who is calling the server. Location comes from Vercel's geo headers,
// device details come from headers the iOS app sends with every request.
export function connectionInfo(req) {
  const ip = clientIP(req)
  const userAgent = header(req, 'user-agent', 500)
  const clientId = header(req, 'x-client-id', 100)
    || createHash('sha256').update(`${ip}|${userAgent}`).digest('hex').slice(0, 32)

  return {
    clientId,
    ip,
    city: decoded(header(req, 'x-vercel-ip-city')),
    region: header(req, 'x-vercel-ip-country-region'),
    country: header(req, 'x-vercel-ip-country'),
    latitude: numberOrNull(header(req, 'x-vercel-ip-latitude')),
    longitude: numberOrNull(header(req, 'x-vercel-ip-longitude')),
    deviceModel: header(req, 'x-device-model', 100),
    osVersion: header(req, 'x-os-version', 100),
    appVersion: header(req, 'x-app-version', 100),
    userAgent,
    path: (req.url || '/').split('?')[0].slice(0, 200),
    seenAt: new Date(),
  }
}

export async function recordConnection(db, req) {
  if (typeof db?.recordConnection !== 'function') return
  try {
    await db.recordConnection(connectionInfo(req))
  } catch (error) {
    console.error('Could not record connection', error)
  }
}
