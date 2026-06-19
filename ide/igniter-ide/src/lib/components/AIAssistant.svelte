<script lang="ts">
  import { createEventDispatcher, tick } from 'svelte'
  import { settings } from '$lib/stores/settings'
  import { streamChat, parseSegments } from '$lib/llm'
  import type { ChatMessage, Segment } from '$lib/llm'
  import type { DiagnosticInfo } from '$lib/types'

  export let editorContent: string = ''
  export let filePath: string = ''
  export let diagnostics: DiagnosticInfo[] = []

  const dispatch = createEventDispatcher<{
    insertCode: string
    replaceFile: string
  }>()

  // ������ State ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let messages: ChatMessage[] = []
  let streamingContent = ''
  let isStreaming = false
  let error = ''
  let input = ''
  let inputEl: HTMLTextAreaElement
  let scrollEl: HTMLDivElement

  // ������ System prompt ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  const DSL_REFERENCE = `\`\`\`
contract Name {
  input  field:   Type
  compute node,   depends_on: [:field], call: MyClass
  output  result: Type, from: :node
}
\`\`\``

  $: systemPrompt = buildSystem(filePath, editorContent, diagnostics)

  function buildSystem(fp: string, content: string, diags: DiagnosticInfo[]): string {
    let s = `You are an expert AI assistant embedded in Igniter IDE.

Igniter is a Ruby gem for declaring business logic as validated dependency graphs.

## DSL Quick Reference
${DSL_REFERENCE}

Keywords: \`contract\` \`input\` \`compute\` \`output\` \`def\` \`module\` \`import\` \`loop\` \`invariant\` \`snapshot\` \`read\`.

Rules:
- \`compute\` uses \`depends_on:\` (alias \`with:\`) for deps and \`call:\` for the callable class.
- \`output\` must reference an existing compute or input node via \`from:\`.
- Types: Integer, Float, String, Bool, Decimal, Collection[T], Option[T].

Keep answers concise. Use fenced code blocks (\`\`\`igniter) for Igniter code.`

    if (fp) {
      const name = fp.split('/').pop() ?? fp
      s += `\n\n## Active File: \`${name}\`\n\`\`\`igniter\n${content || '(empty)'}\n\`\`\``
    }

    if (diags.length > 0) {
      s += '\n\n## Current Diagnostics\n'
      for (const d of diags.slice(0, 10)) {
        s += `- **${d.severity.toUpperCase()}** \`${d.rule}\` line ${d.line ?? '?'}: ${d.message}\n`
      }
    }

    return s
  }

  // ������ Send message ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  async function send() {
    const text = input.trim()
    if (!text || isStreaming) return

    const ai = $settings.ai
    if (!ai.apiKey && ai.provider !== 'ollama') {
      error = `No API key configured. Open Settings (���,) ��� AI Provider.`
      return
    }

    input = ''
    error = ''
    messages = [...messages, { role: 'user', content: text }]
    await tick()
    scrollToBottom()

    isStreaming = true
    streamingContent = ''

    try {
      const gen = streamChat(ai.provider, ai.model, ai.apiKey, ai.baseUrl, messages, systemPrompt)
      for await (const token of gen) {
        streamingContent += token
        scrollToBottom()
      }
      messages = [...messages, { role: 'assistant', content: streamingContent }]
    } catch (e) {
      error = String(e)
    }

    isStreaming = false
    streamingContent = ''
    await tick()
    scrollToBottom()
    inputEl?.focus()
  }

  function scrollToBottom() {
    if (scrollEl) scrollEl.scrollTop = scrollEl.scrollHeight
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send() }
  }

  function clear() {
    messages = []
    streamingContent = ''
    error = ''
  }

  // ������ Suggested prompts ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  const SUGGESTIONS = [
    'Explain this contract',
    'Find potential issues',
    'Add error handling',
    'Generate unit test inputs',
  ]

  function suggest(s: string) { input = s; send() }

  // ������ Copy helper ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  async function copyCode(code: string) {
    try { await navigator.clipboard.writeText(code) } catch {}
  }

  // ������ Markdown-lite renderer ������������������������������������������������������������������������������������������������������������������������������������������������������������
  function renderText(text: string): string {
    return text
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/`([^`]+)`/g, '<code class="bg-gray-800 px-1 rounded text-blue-300">$1</code>')
      .replace(/\n/g, '<br>')
  }
</script>

<div class="flex flex-col h-full overflow-hidden bg-gray-950">

  <!-- Header -->
  <div class="flex items-center justify-between px-3 py-2 border-b border-gray-800 bg-gray-900 shrink-0">
    <div class="flex items-center gap-2">
      <span class="text-purple-400">���</span>
      <span class="text-xs font-bold text-gray-300">AI Assistant</span>
      <span class="text-[10px] text-gray-600">{$settings.ai.provider} �� {$settings.ai.model.split('-').slice(-2).join('-')}</span>
    </div>
    {#if messages.length > 0}
      <button on:click={clear}
        class="text-[10px] text-gray-600 hover:text-gray-400 transition-colors">
        Clear
      </button>
    {/if}
  </div>

  <!-- Messages -->
  <div bind:this={scrollEl} class="flex-1 overflow-y-auto min-h-0 p-3 space-y-3">

    {#if messages.length === 0 && !isStreaming}
      <!-- Empty state with suggestions -->
      <div class="text-center py-4 select-none">
        <div class="text-3xl mb-2 opacity-20">���</div>
        {#if filePath}
          <p class="text-[11px] text-gray-600 mb-3">
            Context: <span class="text-gray-500">{filePath.split('/').pop()}</span>
          </p>
        {:else}
          <p class="text-[11px] text-gray-600 mb-3">Open a file to add context</p>
        {/if}
        <div class="flex flex-col gap-1.5">
          {#each SUGGESTIONS as s}
            <button
              on:click={() => suggest(s)}
              class="text-[11px] text-left px-2.5 py-1.5 rounded-lg bg-gray-900
                     border border-gray-800 hover:border-purple-700 hover:text-purple-300
                     text-gray-500 transition-colors">
              {s}
            </button>
          {/each}
        </div>
      </div>
    {/if}

    <!-- Message history -->
    {#each messages as msg, i (i)}
      {#if msg.role === 'user'}
        <!-- User bubble -->
        <div class="flex justify-end">
          <div class="max-w-[85%] bg-blue-900/60 border border-blue-800/50 rounded-2xl rounded-tr-sm
                      px-3 py-2 text-xs text-blue-100 leading-relaxed">
            {msg.content}
          </div>
        </div>
      {:else}
        <!-- Assistant message with segments -->
        <div class="flex flex-col gap-1.5">
          <span class="text-[10px] text-gray-600 ml-1">��� assistant</span>
          {#each parseSegments(msg.content) as seg}
            {#if seg.type === 'text'}
              <div class="text-xs text-gray-300 leading-relaxed px-1">{@html renderText(seg.content)}</div>
            {:else}
              {@const code = seg.content}
              <div class="rounded-lg overflow-hidden border border-gray-800">
                <div class="flex items-center justify-between px-3 py-1
                            bg-gray-900 border-b border-gray-800">
                  <span class="text-[10px] text-gray-600">{seg.lang || 'code'}</span>
                  <div class="flex items-center gap-2">
                    <button
                      on:click={() => copyCode(code)}
                      class="text-[10px] text-gray-600 hover:text-gray-300 transition-colors">
                      ���� Copy
                    </button>
                    <button
                      on:click={() => dispatch('insertCode', code)}
                      class="text-[10px] text-blue-500 hover:text-blue-300 transition-colors">
                      ��� Insert
                    </button>
                    <button
                      on:click={() => dispatch('replaceFile', code)}
                      class="text-[10px] text-purple-500 hover:text-purple-300 transition-colors">
                      ��� Replace
                    </button>
                  </div>
                </div>
                <pre class="text-[11px] text-gray-200 p-3 overflow-x-auto leading-relaxed font-mono bg-gray-950/80">{code}</pre>
              </div>
            {/if}
          {/each}
        </div>
      {/if}
    {/each}

    <!-- Streaming bubble -->
    {#if isStreaming && streamingContent}
      <div class="flex flex-col gap-1.5">
        <span class="text-[10px] text-gray-600 ml-1">��� assistant</span>
        {#each parseSegments(streamingContent) as seg}
          {#if seg.type === 'text'}
            <div class="text-xs text-gray-300 leading-relaxed px-1">{@html renderText(seg.content)}</div>
          {:else}
            <div class="rounded-lg border border-gray-800 overflow-hidden">
              <div class="px-3 py-1 bg-gray-900 border-b border-gray-800">
                <span class="text-[10px] text-gray-600">{seg.lang}</span>
              </div>
              <pre class="text-[11px] text-gray-200 p-3 overflow-x-auto font-mono bg-gray-950/80">{seg.content}</pre>
            </div>
          {/if}
        {/each}
        <!-- Cursor blink -->
        <span class="inline-block w-1.5 h-3.5 bg-purple-400 rounded-sm ml-1 animate-pulse"></span>
      </div>
    {:else if isStreaming}
      <div class="flex items-center gap-2 text-gray-600 text-xs">
        <span class="animate-spin">���</span> Thinking���
      </div>
    {/if}

  </div>

  <!-- Error -->
  {#if error}
    <div class="mx-3 mb-2 p-2 bg-red-950/60 border border-red-800 rounded text-[11px] text-red-400">
      {error}
    </div>
  {/if}

  <!-- Context indicator -->
  {#if filePath}
    <div class="mx-3 mb-1 flex items-center gap-1.5 text-[10px] text-gray-700">
      <span class="text-green-600">���</span>
      <span class="truncate" title={filePath}>{filePath.split('/').pop()}</span>
      {#if diagnostics.length > 0}
        <span class="text-red-500">�� {diagnostics.filter(d=>d.severity==='error').length} errors</span>
      {/if}
    </div>
  {/if}

  <!-- Input area -->
  <div class="shrink-0 border-t border-gray-800 p-3 pt-2">
    <div class="flex gap-2 items-end">
      <textarea
        bind:this={inputEl}
        bind:value={input}
        on:keydown={onKeydown}
        placeholder="Ask about this contract��� (��� send, ������ newline)"
        rows="2"
        disabled={isStreaming}
        class="flex-1 bg-gray-900 border border-gray-700 rounded-lg px-3 py-2
               text-xs text-gray-200 outline-none focus:border-purple-600
               placeholder:text-gray-700 resize-none transition-colors
               disabled:opacity-50 leading-relaxed"
      ></textarea>
      <button
        on:click={send}
        disabled={isStreaming || !input.trim()}
        class="shrink-0 w-8 h-8 flex items-center justify-center rounded-lg
               text-sm transition-colors
               {isStreaming || !input.trim()
                 ? 'bg-gray-800 text-gray-600 cursor-not-allowed'
                 : 'bg-purple-700 hover:bg-purple-600 text-white'}"
        title="Send (���)">
        {isStreaming ? '���' : '���'}
      </button>
    </div>
  </div>

</div>
