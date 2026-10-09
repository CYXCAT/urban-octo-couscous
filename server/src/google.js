import { createRemoteJWKSet, jwtVerify } from 'jose'
import { HttpError } from './errors.js'

const jwks = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'))

export async function verifyGoogleIDToken(idToken, clientId) {
  let payload
  try {
    ;({ payload } = await jwtVerify(idToken, jwks, {
      issuer: ['https://accounts.google.com', 'accounts.google.com'],
      audience: clientId,
      clockTolerance: 30,
    }))
  } catch {
    throw new HttpError(401, 'Google 登录无效')
  }

  if (!payload.sub) throw new HttpError(401, 'Google 登录无效')
  if (payload.email_verified === false) {
    throw new HttpError(401, 'Google 账号邮箱尚未验证')
  }

  const email = payload.email || `${payload.sub}@users.google.invalid`
  const name = payload.name || payload.email || 'Google 用户'
  return {
    sub: String(payload.sub),
    email: String(email),
    name: String(name),
    picture: payload.picture ? String(payload.picture) : null,
  }
}
