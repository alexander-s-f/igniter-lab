<script lang="ts">
  import { tick, createEventDispatcher } from 'svelte'
  import { api } from '$lib/api'
  import { artifacts } from '$lib/stores/artifacts'
  import type { TracedResult } from '$lib/types'

  export let contractName: string = ''
  export let open: boolean = false

  const dispatch = createEventDispatcher<{ close: void; ran: any }>()

  // ������ Input detection from IR ������������������������������������������������������������������������������������������������������������������������������������������������������
  interface InputField { name: string; type: string }

  let inputFields: InputField[] = []
  let inputs: Record<string, string> = {}
  let irLoaded = false
  let irError = ''

  $: if (open && contractName) loadIr()
  $: if (!open) { result = null; traceRows = []; error = '' }

  async function loadIr() {
    irLoaded = false; irError = ''
    try {
      const ir = await api.getContractIr(contractName)
      const ports: any[] = ir?.input_ports ?? ir?.inputs ?? []
      inputFields = ports.map((p: any) => ({
        name:  p.name  as string,
        type: (p.type_tag ?? p.type?.name ?? 'String') as string,
      }))
      // Preserve existing values, initialize new fields
      const next: Record<string, string> = {}
      for (const f of inputFields) next[f.name] = inputs[f.name] ?? ''
      inputs = next
      irLoaded = true
      await tick()
      firstInputEl?.focus()
    } catch (e) {
      irError = String(e)
      inputFields = []
    }
  }

  // ������ Run state ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let isRunning = false
  let result: any = null
  let traceRows: any[] = []
  let error = ''
  let durationMs = 0
  let firstInputEl: HTMLInputElement | null = null

  // Svelte action: focus the element if it's the first input
  function firstFocus(node: HTMLInputElement, isFirst: boolean) {
    if (isFirst) firstInputEl = node
    return {}
  }

  function getRunErrorStage(err: string): string {
    const msg = err.toLowerCase()
    if (msg.includes('missing loop collection') || msg.includes('ast') || msg.includes('unsupported ast') || msg.includes('not found') || msg.includes('requires matching capability')) {
      return 'VM compile'
    }
    return 'VM run'
  }

  async function run() {
    if (isRunning || !contractName) return
    isRunning = true; error = ''; result = null; traceRows = []

    // Coerce input strings to appropriate types
    const inputObj: Record<string, any> = {}
    for (const [k, v] of Object.entries(inputs)) {
      if (v === '') continue
      const n = Number(v)
      if (!isNaN(n) && v.trim() !== '') { inputObj[k] = n; continue }
      if (v === 'true')  { inputObj[k] = true;  continue }
      if (v === 'false') { inputObj[k] = false; continue }
      try { inputObj[k] = JSON.parse(v) } catch { inputObj[k] = v }
    }

    const ts = Date.now()
    try {
      const traced: TracedResult = await api.dispatchTraced(contractName, inputObj)
      durationMs = Date.now() - ts
      result    = traced.result
      traceRows = traced.trace ?? []

      if (traced.success) {
        artifacts.addDebugEvent({
          type: 'run',
          timestamp: ts,
          contractName,
          success: true,
          durationMs,
          inputs: inputObj,
          result: traced.result,
          boundaryPhase: traced.boundary_phase,
          diagnostics: traced.diagnostics,
          passportSummary: traced.passport_summary,
          loaderDecision: traced.loader_decision,
          ffiObservations: traced.ffi_observations
        })
        dispatch('ran', { contractName, inputs: inputObj, result: traced.result, durationMs })
      } else {
        error = traced.error_message || 'Execution failed'
        artifacts.addDebugEvent({
          type: 'run',
          timestamp: ts,
          contractName,
          success: false,
          durationMs,
          inputs: inputObj,
          error,
          errorStage: traced.boundary_phase,
          boundaryPhase: traced.boundary_phase,
          diagnostics: traced.diagnostics,
          passportSummary: traced.passport_summary,
          loaderDecision: traced.loader_decision,
          ffiObservations: traced.ffi_observations
        })
        dispatch('ran', { contractName, inputs: inputObj, result: null, durationMs, error })
      }
    } catch (e) {
      durationMs = Date.now() - ts
      error = String(e)
      artifacts.addDebugEvent({
        type: 'run',
        timestamp: ts,
        contractName,
        success: false,
        durationMs,
        inputs: inputObj,
        error,
        errorStage: 'execution',
        boundaryPhase: 'execution',
        diagnostics: [],
        passportSummary: null,
        loaderDecision: 'rejected: ' + error,
        ffiObservations: []
      })
      dispatch('ran', { contractName, inputs: inputObj, result: null, durationMs, error })
    }
    isRunning = false
  }

  function onPanelKey(e: KeyboardEvent) {
    if (e.key === 'Escape')                            { e.stopPropagation(); dispatch('close') }
    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') { e.preventDefault();  run() }
  }

  // ������ JSON syntax highlighter (returns HTML string) ������������������������������������������������������������������������������������
  function syntaxHtml(v: unknown, depth = 0): string {
    const ind  = '  '.repeat(depth)
    const ind1 = '  '.repeat(depth + 1)

    if (v === null)             return '<span class="text-warm/40">null</span>'
    if (v === undefined)        return '<span class="text-warm/40">undefined</span>'
    if (typeof v === 'boolean') return `<span class="text-escape font-semibold">${v}</span>`
    if (typeof v === 'number')  return `<span class="text-temporal">${v}</span>`
    if (typeof v === 'string')  return `<span class="text-core">"${escHtml(v)}"</span>`

    if (Array.isArray(v)) {
      if (v.length === 0) return '<span class="text-warm/40">[]</span>'
      const items = v.map(item => `${ind1}${syntaxHtml(item, depth + 1)}`).join(',\n')
      return `<span class="text-warm/50">[</span>\n${items}\n${ind}<span class="text-warm/50">]</span>`
    }

    if (typeof v === 'object') {
      const entries = Object.entries(v as Record<string, unknown>)
      if (entries.length === 0) return '<span class="text-warm/40">{}</span>'
      const lines = entries.map(([k, val]) =>
        `${ind1}<span class="text-ignite">"${escHtml(k)}"</span><span class="text-warm/30">: </span>${syntaxHtml(val, depth + 1)}`
      ).join(',\n')
      return `<span class="text-warm/50">{</span>\n${lines}\n${ind}<span class="text-warm/50">}</span>`
    }

    return escHtml(String(v))
  }

  function escHtml(s: string): string {
    return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
  }

  function placeholder(type: string): string {
    const t = type.toLowerCase()
    if (t.includes('int') || t.includes('float') || t.includes('decimal')) return '0'
    if (t.includes('bool')) return 'true'
    return 'value'
  }
</script>

<!-- Keyboard handler scoped to this panel -->
<svelte:window on:keydown={onPanelKey} />

{#if open}
  <!-- Click-outside backdrop -->
  <div
    class="absolute inset-0 z-20"
    on:click={() => dispatch('close')}
    role="presentation"
  ></div>

  <!-- Slide-in panel -->
  <!-- svelte-ignore a11y_interactive_supports_focus -->
  <div
    class="absolute top-0 right-0 bottom-0 z-30 w-96 flex flex-col
           bg-ink-1/95 backdrop-blur-sm border-l border-ink-line shadow-2xl run-panel"
    role="dialog" aria-label="Inline run panel"
    on:click|stopPropagation={() => {}}
    on:keydown|stopPropagation={onPanelKey}
  >

    <!-- ������ Header ��������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������� -->
    <div class="flex items-center gap-2 px-4 py-2.5 border-b border-ink-line bg-ink-1 shrink-0">
      <span class="text-core">���</span>
      <span class="text-xs font-bold text-warm-3 truncate flex-1">{contractName}</span>
      <kbd class="text-[10px] text-warm/40 bg-ink-2 border border-ink-line px-1.5 rounded hidden sm:inline">������</kbd>
      <button
        on:click={() => dispatch('close')}
        class="text-warm/40 hover:text-warm-3 w-5 h-5 flex items-center justify-center
               rounded hover:bg-ink-2 transition-colors text-xs ml-1 cursor-pointer">���</button>
    </div>

    <!-- ������ Inputs ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������ -->
    <div class="shrink-0 px-4 pt-3 pb-2">
      <div class="flex items-center justify-between mb-2">
        <span class="text-[10px] font-bold text-warm/40 uppercase tracking-wider">Inputs</span>
        {#if irError}
          <span class="text-[10px] text-escape font-semibold" title={irError}>compile first</span>
        {:else if !irLoaded}
          <span class="text-[10px] text-warm/40 animate-pulse">detecting���</span>
        {:else}
          <span class="text-[10px] text-warm/40">{inputFields.length} field{inputFields.length !== 1 ? 's' : ''}</span>
        {/if}
      </div>

      {#if irLoaded}
        {#if inputFields.length === 0}
          <p class="text-xs text-warm/40 italic py-1">No inputs required.</p>
        {:else}
          <div class="space-y-2">
            {#each inputFields as field, i}
              <div class="flex items-center gap-2">
                <label
                  class="text-xs text-warm/50 w-24 shrink-0 truncate font-mono"
                  title={field.name}>{field.name}</label>
                <input
                  use:firstFocus={i === 0}
                  type="text"
                  bind:value={inputs[field.name]}
                  placeholder={placeholder(field.type)}
                  on:keydown={(e) => {
                    if (e.key === 'Enter' && !e.metaKey && !e.ctrlKey) run()
                  }}
                  class="flex-1 bg-ink-3 border border-ink-line/80 rounded px-2 py-1
                         text-xs text-warm-3 outline-none focus:border-ignite
                         placeholder:text-warm/20 font-mono min-w-0 transition-colors"
                />
                <span class="text-[10px] text-warm/40 shrink-0 w-14 truncate text-right"
                      title={field.type}>{field.type}</span>
              </div>
            {/each}
          </div>
        {/if}
      {:else if !irError}
        <!-- Skeleton -->
        <div class="space-y-2 animate-pulse">
          {#each [1, 2] as _}
            <div class="flex items-center gap-2">
              <div class="h-4 w-20 bg-ink-2 rounded shrink-0"></div>
              <div class="h-6 flex-1 bg-ink-2 rounded"></div>
            </div>
          {/each}
        </div>
      {/if}
    </div>

    <!-- ������ Run button ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������ -->
    <div class="px-4 pb-3 shrink-0">
      <button
        on:click={run}
        disabled={isRunning}
        class="w-full py-1.5 rounded text-xs font-bold transition-colors flex items-center justify-center gap-2 cursor-pointer
               {isRunning
                 ? 'bg-ink-2 text-warm/30 border border-ink-line/30 cursor-not-allowed'
                 : 'bg-core text-ink-1 hover:bg-core/85 border border-core/20'}"
      >
        {#if isRunning}
          <span class="inline-block animate-spin">���</span> Running���
        {:else}
          ��� Run
        {/if}
      </button>
    </div>

    <div class="border-t border-ink-line shrink-0"></div>

    <!-- ������ Result ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������ -->
    <div class="flex-1 overflow-y-auto min-h-0 text-xs font-mono">

      {#if !result && !error && !isRunning}
        <div class="flex flex-col items-center justify-center h-full gap-2 text-warm/30 select-none py-8">
          <span class="text-4xl opacity-10">���</span>
          <span class="italic font-sans text-xs">Press ������ to run</span>
        </div>

      {:else if isRunning}
        <div class="flex items-center justify-center gap-2 text-warm/40 py-8">
          <span class="animate-spin">���</span>
          <span class="font-sans">Executing���</span>
        </div>

      {:else if error}
        <div class="p-4">
          <div class="flex items-center gap-2 mb-2">
            <span class="text-[10px] font-bold text-warm/40 uppercase tracking-wider font-sans">Error</span>
            <span class="text-oof text-[10px]">{durationMs}ms</span>
          </div>
          <pre class="text-oof whitespace-pre-wrap break-words leading-relaxed text-[11px]">{error}</pre>
        </div>

      {:else if result !== null}
        <!-- Result header -->
        <div class="flex items-center gap-2 px-4 py-1.5 bg-ink-1 border-b border-ink-line sticky top-0">
          <span class="text-[10px] font-bold text-warm/40 uppercase tracking-wider font-sans">Output</span>
          <span class="text-core text-[10px]">���</span>
          <span class="text-core/70 text-[10px]">{durationMs}ms</span>
        </div>

        <!-- Syntax-highlighted JSON -->
        <pre class="px-4 py-3 leading-relaxed text-[11px] overflow-x-auto">{@html syntaxHtml(result)}</pre>

        <!-- Trace -->
        {#if traceRows.length > 0}
          <div class="border-t border-ink-line">
            <div class="px-4 py-1.5 bg-ink-1 sticky top-0">
              <span class="text-[10px] font-bold text-warm/40 uppercase tracking-wider font-sans">
                Trace ��� {traceRows.length} nodes
              </span>
            </div>
            {#each traceRows as step (step.order)}
              <div class="flex items-center gap-2 px-4 py-1 border-b border-ink-line/30 hover:bg-ink-2 transition-colors">
                <span class="text-warm/30 text-[10px] w-4 shrink-0 tabular-nums">{step.order}</span>
                <span class="text-[10px] w-12 shrink-0 font-semibold
                       {step.kind === 'input'   ? 'text-temporal'
                        : step.kind === 'output' ? 'text-ember'
                        : 'text-warm/40'}">{step.kind}</span>
                <span class="text-warm-3 text-[10px] flex-1 truncate">{step.node}</span>
                <span class="text-warm/50 text-[10px] truncate max-w-28"
                      title={step.value_preview}>{step.value_preview}</span>
              </div>
            {/each}
          </div>
        {/if}
      {/if}

    </div>
  </div>
{/if}

<style>
  .run-panel {
    animation: slide-in 0.14s cubic-bezier(0.16, 1, 0.3, 1);
  }
  @keyframes slide-in {
    from { transform: translateX(100%); opacity: 0 }
    to   { transform: translateX(0);    opacity: 1 }
  }
</style>
