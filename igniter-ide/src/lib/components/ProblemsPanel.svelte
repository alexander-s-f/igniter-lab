<script lang="ts">
  import { createEventDispatcher } from 'svelte'
  import type { DiagnosticInfo } from '$lib/types'

  interface TabEntry { path: string; diagnostics: DiagnosticInfo[] }
  export let openTabs: TabEntry[] = []

  const dispatch = createEventDispatcher<{ jumpTo: { path: string; line: number } }>()

  interface Problem extends DiagnosticInfo {
    path: string
    filename: string
  }

  $: problems = openTabs.flatMap(t =>
    t.diagnostics.map(d => ({
      ...d,
      path: t.path,
      filename: t.path.split('/').pop() ?? t.path,
    }))
  )

  $: errorCount   = problems.filter(p => p.severity === 'error').length
  $: warningCount = problems.filter(p => p.severity === 'warning').length

  const SEV_ICON: Record<string, string> = { error: '���', warning: '���', info: '���' }
  const SEV_COLOR: Record<string, string> = {
    error:   'text-oof',
    warning: 'text-escape',
    info:    'text-temporal',
  }
  const SEV_BG: Record<string, string> = {
    error:   'hover:bg-oof/10',
    warning: 'hover:bg-escape/10',
    info:    'hover:bg-temporal/10',
  }

  function jump(p: Problem) {
    dispatch('jumpTo', { path: p.path, line: p.line ?? 1 })
  }
</script>

<div class="flex flex-col h-full text-xs font-mono">
  <!-- Summary bar -->
  <div class="flex items-center gap-3 px-3 py-1.5 border-b border-ink-line bg-ink-1 shrink-0">
    {#if errorCount > 0}
      <span class="text-oof flex items-center gap-1">
        <span class="font-bold">���</span> {errorCount} error{errorCount !== 1 ? 's' : ''}
      </span>
    {/if}
    {#if warningCount > 0}
      <span class="text-escape flex items-center gap-1">
        <span class="font-bold">���</span> {warningCount} warning{warningCount !== 1 ? 's' : ''}
      </span>
    {/if}
    {#if problems.length === 0}
      <span class="text-core flex items-center gap-1.5 font-semibold">
        <span>���</span> No problems
      </span>
    {/if}
    <span class="ml-auto text-warm/40">{openTabs.length} file{openTabs.length !== 1 ? 's' : ''} checked</span>
  </div>

  <!-- Problem list -->
  <div class="flex-1 overflow-y-auto">
    {#if problems.length === 0}
      <div class="flex flex-col items-center justify-center h-full gap-2 text-warm/40 select-none py-8">
        <span class="text-2xl opacity-30">���</span>
        <span class="italic">No problems detected</span>
      </div>
    {:else}
      {#each problems as p (p.path + (p.line ?? 0) + p.rule)}
        <button
          class="w-full flex items-start gap-2 px-3 py-1.5 border-b border-ink-line/50 text-left
                 transition-colors cursor-pointer {SEV_BG[p.severity] ?? 'hover:bg-ink-2'}"
          on:click={() => jump(p)}
        >
          <!-- severity icon -->
          <span class="shrink-0 font-bold mt-px {SEV_COLOR[p.severity] ?? 'text-warm/50'}">
            {SEV_ICON[p.severity] ?? '��'}
          </span>

          <!-- message -->
          <span class="flex-1 min-w-0">
            <span class="text-warm-3 break-words">{p.message}</span>
            <span class="ml-1.5 text-warm/30 text-[10px]">{p.rule}</span>
          </span>

          <!-- file + location -->
          <span class="shrink-0 text-warm/40 text-[10px] ml-2 whitespace-nowrap">
            {p.filename}{p.line ? `:${p.line}` : ''}
          </span>
        </button>
      {/each}
    {/if}
  </div>
</div>
