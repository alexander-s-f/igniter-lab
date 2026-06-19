<script lang="ts">
  import { onMount } from 'svelte'
  import { api } from '$lib/api'
  import { marked } from 'marked'

  export let path: string = ''
  export let title: string = 'Documentation'

  let markdown = ''
  let html = ''
  let loading = false
  let error = ''

  $: if (path) {
    loadDoc(path)
  }

  async function loadDoc(docPath: string) {
    loading = true
    error = ''
    try {
      const content = await api.readFile(docPath)
      markdown = content
      html = await marked.parse(content)
    } catch (e) {
      error = `Failed to load document: ${String(e)}`
    } finally {
      loading = false
    }
  }
</script>

<div class="h-full w-full flex flex-col bg-gray-950 overflow-hidden select-text">
  <!-- Header -->
  <div class="flex items-center justify-between px-5 py-3.5 bg-gray-900 border-b border-gray-800 shrink-0">
    <div class="flex items-center gap-2.5">
      <span class="text-blue-400 font-bold tracking-wider text-[10px] uppercase">Manual</span>
      <span class="text-gray-700">|</span>
      <span class="text-sm font-semibold text-gray-200">{title}</span>
    </div>
    <span class="text-[10px] text-gray-600 font-mono truncate max-w-72" title={path}>{path}</span>
  </div>

  <!-- Content Container -->
  <div class="flex-1 overflow-y-auto px-6 py-6 scrollbar-thin">
    {#if loading}
      <div class="h-full flex items-center justify-center text-xs text-gray-500 gap-2">
        <span class="animate-spin text-sm">���</span>
        Loading manual chapter���
      </div>
    {:else if error}
      <div class="max-w-xl mx-auto p-4 bg-red-950/40 border border-red-900/50 rounded-lg text-xs text-red-400 font-mono">
        {error}
      </div>
    {:else}
      <article class="prose max-w-3xl mx-auto text-gray-300 text-sm leading-relaxed pb-12">
        <!-- Rendered Markdown HTML -->
        <div class="markdown-body">
          {@html html}
        </div>
      </article>
    {/if}
  </div>
</div>

<style>
  /* Premium Dark Mode Markdown Stylesheet */
  :global(.markdown-body) {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  }
  :global(.markdown-body h1) {
    font-size: 1.6rem;
    font-weight: 800;
    color: #f3f4f6; /* text-gray-100 */
    border-bottom: 1px solid #1f2937;
    padding-bottom: 0.5rem;
    margin-top: 1.5rem;
    margin-bottom: 1rem;
    letter-spacing: -0.025em;
  }
  :global(.markdown-body h2) {
    font-size: 1.3rem;
    font-weight: 700;
    color: #e5e7eb; /* text-gray-200 */
    border-bottom: 1px solid #111827;
    padding-bottom: 0.3rem;
    margin-top: 2rem;
    margin-bottom: 0.8rem;
    letter-spacing: -0.02em;
  }
  :global(.markdown-body h3) {
    font-size: 1.1rem;
    font-weight: 600;
    color: #f3f4f6;
    margin-top: 1.5rem;
    margin-bottom: 0.5rem;
  }
  :global(.markdown-body p) {
    margin-bottom: 1rem;
    color: #d1d5db; /* text-gray-300 */
  }
  :global(.markdown-body a) {
    color: #3b82f6; /* text-blue-500 */
    text-decoration: none;
    border-bottom: 1px dashed rgba(59, 130, 246, 0.4);
    transition: all 0.2s ease;
  }
  :global(.markdown-body a:hover) {
    color: #60a5fa;
    border-bottom-style: solid;
  }
  :global(.markdown-body ul) {
    list-style-type: disc;
    padding-left: 1.5rem;
    margin-bottom: 1rem;
    space-y: 0.25rem;
  }
  :global(.markdown-body ol) {
    list-style-type: decimal;
    padding-left: 1.5rem;
    margin-bottom: 1rem;
  }
  :global(.markdown-body li) {
    margin-bottom: 0.3rem;
    color: #d1d5db;
  }
  :global(.markdown-body blockquote) {
    border-left: 4px solid #3b82f6;
    background: rgba(30, 41, 59, 0.25);
    padding: 0.75rem 1rem;
    margin: 1rem 0;
    border-radius: 0 6px 6px 0;
    color: #9ca3af;
  }
  :global(.markdown-body blockquote p) {
    margin-bottom: 0;
  }
  :global(.markdown-body table) {
    width: 100%;
    border-collapse: collapse;
    margin: 1.5rem 0;
    font-size: 12px;
  }
  :global(.markdown-body th) {
    background-color: #111827;
    color: #9ca3af;
    font-weight: 600;
    text-align: left;
    padding: 0.5rem 0.75rem;
    border: 1px solid #1f2937;
  }
  :global(.markdown-body td) {
    padding: 0.5rem 0.75rem;
    border: 1px solid #1f2937;
    color: #d1d5db;
  }
  :global(.markdown-body tr:nth-child(even)) {
    background-color: rgba(17, 24, 39, 0.2);
  }
  :global(.markdown-body code) {
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    font-size: 0.85em;
    background: rgba(31, 41, 55, 0.6);
    color: #60a5fa;
    padding: 0.15rem 0.35rem;
    border-radius: 4px;
    border: 1px solid rgba(255, 255, 255, 0.05);
  }
  :global(.markdown-body pre) {
    background: #030712;
    border: 1px solid #1f2937;
    border-radius: 8px;
    padding: 1rem;
    overflow-x: auto;
    margin: 1.25rem 0;
  }
  :global(.markdown-body pre code) {
    background: transparent;
    color: #e5e7eb;
    padding: 0;
    border-radius: 0;
    border: none;
    font-size: 0.9em;
    line-height: 1.5;
  }
  :global(.markdown-body hr) {
    border: 0;
    border-top: 1px solid #1f2937;
    margin: 2rem 0;
  }
</style>
