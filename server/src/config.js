const defaultClientID = '107833156473-ckhr78k7vplu3rfgppn62825h6ipph7u.apps.googleusercontent.com'

export function loadConfig(env = process.env) {
  const port = Number(env.PORT || 8787)
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT 无效')
  }

  return {
    port,
    host: env.HOST || '0.0.0.0',
    googleClientId: (env.GOOGLE_CLIENT_ID || defaultClientID).trim(),
    llmApiKey: (env.LLM_API_KEY || '').trim(),
    llmBaseURL: (env.LLM_BASE_URL || 'https://api.openai.com/v1').trim(),
    llmModel: (env.LLM_MODEL || 'gpt-4o-mini').trim(),
    systemPrompt: (env.LLM_SYSTEM_PROMPT || '你是 hajimi，一个简洁、有用的助手。使用用户所用的语言回答。').trim(),
  }
}
