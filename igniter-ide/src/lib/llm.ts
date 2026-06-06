// ������ Streaming LLM client for Igniter IDE ������������������������������������������������������������������������������������������������������������������
// Supports Anthropic, OpenAI-compatible APIs, and Ollama.

export interface ChatMessage {
  role: 'user' | 'assistant'
  content: string
}

// ������ Anthropic ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
async function* streamAnthropic(
  apiKey: string,
  model: string,
  messages: ChatMessage[],
  system: string
): AsyncGenerator<string> {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model,
      max_tokens: 4096,
      stream: true,
      system,
      messages: messages.map(m => ({ role: m.role, content: m.content })),
    }),
  })
  if (!res.ok) {
    const err = await res.text()
    throw new Error(`Anthropic ${res.status}: ${err}`)
  }
  yield* parseSSE(res, (data) => {
    if (data.type === 'content_block_delta' && data.delta?.type === 'text_delta') {
      return data.delta.text ?? ''
    }
    return ''
  })
}

// ������ OpenAI-compatible ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������
async function* streamOpenAI(
  apiKey: string,
  model: string,
  baseUrl: string,
  messages: ChatMessage[],
  system: string
): AsyncGenerator<string> {
  const url = baseUrl ? `${baseUrl.replace(/\/$/, '')}/v1/chat/completions` : 'https://api.openai.com/v1/chat/completions'
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'authorization': `Bearer ${apiKey}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model,
      stream: true,
      messages: [
        { role: 'system', content: system },
        ...messages.map(m => ({ role: m.role, content: m.content })),
      ],
    }),
  })
  if (!res.ok) {
    const err = await res.text()
    throw new Error(`OpenAI ${res.status}: ${err}`)
  }
  yield* parseSSE(res, (data) => data.choices?.[0]?.delta?.content ?? '')
}

// ������ Ollama ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
async function* streamOllama(
  baseUrl: string,
  model: string,
  messages: ChatMessage[],
  system: string
): AsyncGenerator<string> {
  const url = `${(baseUrl || 'http://localhost:11434').replace(/\/$/, '')}/api/chat`
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      model,
      stream: true,
      messages: [
        { role: 'system', content: system },
        ...messages.map(m => ({ role: m.role, content: m.content })),
      ],
    }),
  })
  if (!res.ok) {
    const err = await res.text()
    throw new Error(`Ollama ${res.status}: ${err}`)
  }
  // Ollama uses NDJSON, not SSE
  const reader = res.body?.getReader()
  if (!reader) return
  const dec = new TextDecoder()
  let buf = ''
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    buf += dec.decode(value, { stream: true })
    const lines = buf.split('\n')
    buf = lines.pop() ?? ''
    for (const line of lines) {
      if (!line.trim()) continue
      try {
        const obj = JSON.parse(line)
        const token = obj.message?.content ?? ''
        if (token) yield token
      } catch {}
    }
  }
}

// ������ SSE parser ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
async function* parseSSE(
  res: Response,
  extract: (data: any) => string
): AsyncGenerator<string> {
  const reader = res.body?.getReader()
  if (!reader) return
  const dec = new TextDecoder()
  let buf = ''
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    buf += dec.decode(value, { stream: true })
    const lines = buf.split('\n')
    buf = lines.pop() ?? ''
    for (const line of lines) {
      if (!line.startsWith('data: ')) continue
      const raw = line.slice(6).trim()
      if (raw === '[DONE]') return
      try {
        const token = extract(JSON.parse(raw))
        if (token) yield token
      } catch {}
    }
  }
}

// ������ Public API ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
export async function* streamChat(
  provider: 'anthropic' | 'openai' | 'ollama',
  model: string,
  apiKey: string,
  baseUrl: string,
  messages: ChatMessage[],
  system: string
): AsyncGenerator<string> {
  if (provider === 'anthropic') {
    yield* streamAnthropic(apiKey, model, messages, system)
  } else if (provider === 'openai') {
    yield* streamOpenAI(apiKey, model, baseUrl, messages, system)
  } else {
    yield* streamOllama(baseUrl, model, messages, system)
  }
}

// ������ Message segment parser (for code block rendering) ���������������������������������������������������������������������������
export type Segment =
  | { type: 'text'; content: string }
  | { type: 'code'; lang: string; content: string }

export function parseSegments(text: string): Segment[] {
  const segments: Segment[] = []
  // Split on fenced code blocks: ```lang\ncode\n```
  const re = /```(\w*)\n?([\s\S]*?)```/g
  let last = 0
  let m: RegExpExecArray | null
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) {
      segments.push({ type: 'text', content: text.slice(last, m.index) })
    }
    segments.push({ type: 'code', lang: m[1] || 'text', content: m[2].trim() })
    last = m.index + m[0].length
  }
  if (last < text.length) {
    segments.push({ type: 'text', content: text.slice(last) })
  }
  return segments
}
