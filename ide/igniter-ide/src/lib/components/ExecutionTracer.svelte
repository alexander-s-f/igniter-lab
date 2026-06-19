<script lang="ts">
  import { onDestroy } from 'svelte'
  import { api } from '$lib/api'
  import type { ContractInfo } from '$lib/types'

  export let contracts: ContractInfo[] = []

  let selectedContract = ''
  let inputsJson = '{}'
  let running = false
  let error = ''
  let traceResult: any = null
  let activeStep = -1
  let animTimer: ReturnType<typeof setInterval> | null = null
  let isAnimating = false

  const KIND_ICON: Record<string, string> = {
    input: '���', output: '���', compute: '���', read: '����',
    loop: '���', service_loop: '���', invariant: '���', snapshot: '����',
    fold_stream: '���', window: '���',
  }

  const KIND_COLOR: Record<string, string> = {
    input:        '#1d4ed8',
    output:       '#7c3aed',
    compute:      '#065f46',
    read:         '#92400e',
    loop:         '#1e3a5f',
    service_loop: '#0f4c75',
    invariant:    '#7f1d1d',
    snapshot:     '#3730a3',
  }

  const FRAG_BORDER: Record<string, string> = {
    core: '#22c55e', escape: '#eab308', temporal: '#06b6d4', oof: '#ef4444', unknown: '#6b7280',
  }

  async function run() {
    if (!selectedContract) return
    let parsed: any = {}
    try { parsed = JSON.parse(inputsJson) } catch { error = 'Invalid JSON inputs'; return }
    running = true; error = ''; traceResult = null; activeStep = -1
    stopAnimation()
    try {
      const res = await api.dispatchTraced(selectedContract, parsed)
      if (res.success) {
        traceResult = res
        startAnimation()
      } else {
        error = `${res.boundary_phase.toUpperCase()} ERROR: ${res.error_message || 'Failed'}`
        traceResult = res
      }
    } catch(e) { error = String(e) }
    finally { running = false }
  }

  function startAnimation() {
    if (!traceResult) return
    isAnimating = true
    activeStep = 0
    animTimer = setInterval(() => {
      activeStep++
      if (activeStep >= traceResult.trace.length) {
        stopAnimation()
        activeStep = traceResult.trace.length - 1
      }
    }, 350)
  }

  function stopAnimation() {
    isAnimating = false
    if (animTimer) { clearInterval(animTimer); animTimer = null }
  }

  function replay() {
    activeStep = -1
    setTimeout(startAnimation, 100)
  }

  onDestroy(stopAnimation)
</script>

<div class="flex gap-4 h-full" style="min-height: 540px">

  <!-- Left: controls -->
  <div class="w-64 shrink-0 space-y-3">
    <div>
      <label class="block text-xs text-gray-400 mb-1">Contract</label>
      <select bind:value={selectedContract}
        class="w-full bg-gray-900 border border-gray-700 rounded px-2 py-1.5 text-sm outline-none focus:border-blue-500">
        <option value="">��� select ���</option>
        {#each contracts as c}
          <option value={c.name}>{c.name}</option>
        {/each}
      </select>
    </div>

    <div>
      <label class="block text-xs text-gray-400 mb-1">Inputs (JSON)</label>
      <textarea bind:value={inputsJson} rows="5"
        class="w-full bg-gray-900 border border-gray-700 rounded px-2 py-1.5 text-xs font-mono outline-none focus:border-blue-500 resize-none"
        placeholder="e.g. &#123;&#125;"/>
    </div>

    <button on:click={run} disabled={running || !selectedContract}
      class="w-full px-3 py-2 bg-green-700 hover:bg-green-600 disabled:bg-gray-700 rounded text-sm font-semibold transition-colors">
      {running ? '... Executing' : '��� Trace Execution'}
    </button>

    {#if traceResult}
      <div class="flex gap-2">
        <button on:click={replay} class="flex-1 px-2 py-1.5 bg-blue-800 hover:bg-blue-700 rounded text-xs transition-colors">
          ��� Replay
        </button>
        <button on:click={stopAnimation} class="flex-1 px-2 py-1.5 bg-gray-700 hover:bg-gray-600 rounded text-xs transition-colors">
          Pause
        </button>
      </div>

      <!-- Stats -->
      <div class="bg-gray-900 border border-gray-800 rounded p-2 text-xs space-y-1">
        <div class="text-gray-400 font-semibold">Execution</div>
        <div>��� <span class="text-yellow-400">{traceResult.total_ms}ms</span></div>
        <div>��� <span class="text-blue-400">{traceResult.trace.length} steps</span></div>
        {#if traceResult.observations.length > 0}
          <div class="pt-1 text-gray-400 font-semibold">Observations</div>
          {#each traceResult.observations as obs}
            <div class="text-cyan-400 truncate">{obs}</div>
          {/each}
        {/if}
      </div>

      <!-- Final Result -->
      <div class="bg-gray-900 border border-gray-800 rounded p-2 text-xs">
        <div class="text-green-400 font-semibold mb-1">Result</div>
        <pre class="text-yellow-300 overflow-auto max-h-28 whitespace-pre-wrap">{JSON.stringify(traceResult.result, null, 2)}</pre>
      </div>
    {/if}

    {#if error}
      <div class="text-red-400 text-xs">x {error}</div>
    {/if}
  </div>

  <!-- Right: trace visualization -->
  <div class="flex-1 overflow-auto">
    {#if !traceResult}
      <div class="flex flex-col items-center justify-center h-full text-gray-600 gap-2">
        <span class="text-4xl">���</span>
        <span class="text-sm">Select a contract and click "Trace Execution"</span>
        <span class="text-xs">See each computation step animate in real-time</span>
      </div>
    {:else}
      <div class="space-y-1 py-2">
        {#each traceResult.trace as step, i}
          {@const isActive = i === activeStep}
          {@const isDone = i < activeStep}
          {@const isPending = i > activeStep}
          {@const kindColor = KIND_COLOR[step.kind] ?? '#374151'}
          {@const fragBorder = FRAG_BORDER[step.fragment_class] ?? '#6b7280'}

          <div class="flex items-start gap-2 px-2 py-1.5 rounded-lg transition-all duration-300"
            style="background: {isActive ? '#1e3a5f' : isDone ? '#111827' : 'transparent'};
                   border: 1px solid {isActive ? '#60a5fa' : isDone ? '#1f2937' : '#0f0f0f'};
                   opacity: {isPending ? 0.35 : 1};">

            <!-- Step number -->
            <span class="text-xs text-gray-600 w-5 flex-shrink-0 mt-0.5 font-mono">{i+1}</span>

            <!-- Kind badge -->
            <span class="text-xs px-1.5 py-0.5 rounded flex-shrink-0"
              style="background: {kindColor}20; color: {kindColor}; border: 1px solid {kindColor}40; font-size:10px">
              {KIND_ICON[step.kind] ?? '���'} {step.kind}
            </span>

            <!-- Node name + deps -->
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <span class="text-sm font-semibold"
                  style="color: {isActive ? '#f3f4f6' : isDone ? '#9ca3af' : '#4b5563'}">
                  {step.node}
                </span>
                <span class="text-xs px-1 rounded"
                  style="border: 1px solid {fragBorder}; color: {fragBorder}; font-size:9px">
                  {step.fragment_class}
                </span>
                {#if isActive}
                  <span class="text-xs text-blue-400 animate-pulse">��� computing</span>
                {/if}
              </div>
              {#if step.deps.length > 0}
                <div class="text-xs text-gray-600 mt-0.5">
                  deps: {step.deps.join(' �� ')}
                </div>
              {/if}
            </div>

            <!-- Value -->
            <div class="text-xs font-mono flex-shrink-0 max-w-32 truncate"
              style="color: {step.kind === 'output' && isDone ? '#fbbf24' : isDone ? '#6ee7b7' : '#4b5563'}">
              {isDone || isActive ? step.value_preview : '���'}
            </div>
          </div>
        {/each}
      </div>
    {/if}
  </div>
</div>
