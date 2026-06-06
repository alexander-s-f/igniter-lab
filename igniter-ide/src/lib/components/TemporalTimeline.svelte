<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import * as d3 from 'd3'
  import { api } from '$lib/api'
  import { listen } from '@tauri-apps/api/event'
  import type { FactInfo, RedactedTraceReceipt } from '$lib/types'

  // Mode switcher state
  let activeMode: 'bitemporal' | 'playback' | 'history' = 'bitemporal'

  // Bitemporal fact explorer state
  let store   = 'leads'
  let key     = ''
  let facts: FactInfo[] = []
  let loading = false
  let error   = ''
  let wrapper: HTMLDivElement
  let svgEl:   SVGSVGElement
  let tooltip: d3.Selection<HTMLDivElement, unknown, null, undefined>

  // Persistent refs updated during zoom
  let baseXScale: d3.ScaleTime<number, number>
  let baseYScale: d3.ScaleTime<number, number>
  let xAxisG:     d3.Selection<SVGGElement, unknown, null, undefined>
  let yAxisG:     d3.Selection<SVGGElement, unknown, null, undefined>
  let dots:       d3.Selection<SVGCircleElement, FactInfo, SVGGElement, unknown>
  let diagLine:   d3.Selection<SVGLineElement, unknown, null, undefined>
  let zoomRef:    d3.ZoomBehavior<SVGSVGElement, unknown>
  let asOfLine:   d3.Selection<SVGLineElement, unknown, null, undefined>
  let asOfLabel:  d3.Selection<SVGTextElement, unknown, null, undefined>

  let asOfTs: number | null = null  // unix timestamp for the as_of cursor

  const MARGIN = { top: 30, right: 30, bottom: 50, left: 82 }

  // Playback Inspector state
  let playbackReceipt: any = null
  let playbackError = ''
  let selectedStep: any = null

  async function loadPlaybackReceipt() {
    playbackError = ''
    try {
      playbackReceipt = await api.readPlaybackReceipt()
      if (!playbackReceipt || typeof playbackReceipt !== 'object' || !playbackReceipt.playback_id || !Array.isArray(playbackReceipt.steps)) {
        playbackReceipt = null
        playbackError = 'Receipt format invalid: missing playback_id or steps'
      }
    } catch (e) {
      playbackReceipt = null
      playbackError = 'No active trace playback receipt found on disk'
    }
  }

  function handleSelectStep(step: any) {
    selectedStep = step
  }

  // Telemetry History state
  let historyReceipts: RedactedTraceReceipt[] = []
  let historyError = ''
  let selectedHistoryEntry: RedactedTraceReceipt | null = null
  let loadingHistory = false

  async function loadTelemetryHistory() {
    historyError = ''
    loadingHistory = true
    try {
      historyReceipts = await api.getTelemetryHistory()
      if (!historyReceipts || !Array.isArray(historyReceipts)) {
        historyReceipts = []
        historyError = 'Telemetry history format invalid: not an array'
      }
    } catch (e) {
      historyReceipts = []
      historyError = 'Failed to load telemetry history from backend'
    } finally {
      loadingHistory = false
    }
  }

  function handleSelectHistoryEntry(entry: RedactedTraceReceipt) {
    selectedHistoryEntry = entry
  }

  async function query() {
    if (!store) return
    loading = true; error = ''
    try {
      facts = await api.readFacts(store, key || 'global', undefined)
      render()
    } catch (e) { error = String(e) }
    finally     { loading = false }
  }

  function dims() {
    const W = svgEl?.clientWidth || 800
    const H = 440
    return {
      W, H,
      w: W - MARGIN.left - MARGIN.right,
      h: H - MARGIN.top  - MARGIN.bottom,
    }
  }

  function fmtTick(d: Date) {
    return `${d.getMonth()+1}/${d.getDate()} ${d.getHours()}:${String(d.getMinutes()).padStart(2,'0')}`
  }

  function render() {
    if (!svgEl || facts.length === 0) return
    const { W, H, w, h } = dims()

    const svg = d3.select(svgEl)
    svg.selectAll('*').remove()
    svg.attr('width', W).attr('height', H)

    // Clip path so points don't overflow axes
    svg.append('defs').append('clipPath')
      .attr('id', 'tl-clip')
      .append('rect').attr('width', w).attr('height', h).attr('x', 0).attr('y', 0)

    const root = svg.append('g')
      .attr('transform', `translate(${MARGIN.left},${MARGIN.top})`)

    const allTx = facts.map(f => f.transaction_time)
    const allVt = facts.map(f => f.valid_time ?? f.transaction_time)
    const pad   = (ext: [number,number]) => {
      const r = ext[1] - ext[0] || 3600
      return [ext[0] - r * 0.06, ext[1] + r * 0.06] as [number, number]
    }

    baseXScale = d3.scaleTime()
      .domain(pad(d3.extent(allTx) as [number,number]).map(t => new Date(t*1000)) as [Date,Date])
      .range([0, w])
    baseYScale = d3.scaleTime()
      .domain(pad(d3.extent(allVt) as [number,number]).map(t => new Date(t*1000)) as [Date,Date])
      .range([h, 0])

    const xAxis = d3.axisBottom<Date>(baseXScale).ticks(6).tickFormat(fmtTick)
    const yAxis = d3.axisLeft<Date>(baseYScale).ticks(6).tickFormat(fmtTick)

    // Grid
    const gridG = root.append('g').attr('class', 'grid')
    gridG.selectAll('line').data(baseYScale.ticks(6)).enter().append('line')
      .attr('x1', 0).attr('x2', w)
      .attr('y1', d => baseYScale(d)).attr('y2', d => baseYScale(d))
      .attr('stroke', '#1f2937').attr('stroke-dasharray', '3,3')

    // Axes
    xAxisG = root.append('g').attr('transform', `translate(0,${h})`).call(xAxis) as any
    yAxisG = root.append('g').call(yAxis) as any

    const styleAxis = (g: d3.Selection<SVGGElement, unknown, null, undefined>) => {
      g.selectAll('text').attr('fill', '#9ca3af').attr('font-size', '10px').attr('font-family', 'ui-monospace, monospace')
      g.select('.domain').attr('stroke', '#374151')
      g.selectAll('.tick line').attr('stroke', '#374151')
    }
    styleAxis(xAxisG); styleAxis(yAxisG)

    // Axis labels
    root.append('text').attr('x', w/2).attr('y', h + 44)
      .attr('fill', '#6b7280').attr('text-anchor', 'middle').attr('font-size', '11px')
      .text('Transaction Time (when recorded)')
    root.append('text').attr('transform', 'rotate(-90)').attr('x', -h/2).attr('y', -64)
      .attr('fill', '#6b7280').attr('text-anchor', 'middle').attr('font-size', '11px')
      .text('Valid Time (logical truth)')

    // Diagonal tx = valid reference line
    const tMin = Math.max(allTx[0], allVt[0]) * 1000
    const tMax = Math.min(allTx[allTx.length-1] ?? 0, allVt[allVt.length-1] ?? 0) * 1000
    diagLine = root.append('line')
      .attr('x1', baseXScale(new Date(tMin))).attr('y1', baseYScale(new Date(tMin)))
      .attr('x2', baseXScale(new Date(tMax))).attr('y2', baseYScale(new Date(tMax)))
      .attr('stroke', '#374151').attr('stroke-dasharray', '6,3').attr('stroke-width', 1)

    // as_of line
    asOfLine  = root.append('line').attr('y1', 0).attr('y2', h).attr('stroke', '#f59e0b').attr('stroke-width', 1.5).attr('stroke-dasharray', '4,2').style('display', 'none')
    asOfLabel = root.append('text').attr('y', 14).attr('fill', '#f59e0b').attr('font-size', '10px').text('as_of').style('display', 'none')
    if (asOfTs !== null) updateAsOf(baseXScale)

    // Tooltip div
    if (!tooltip) {
      tooltip = d3.select(wrapper).append('div')
        .style('position','absolute').style('background','#111827')
        .style('border','1px solid #374151').style('border-radius','8px')
        .style('padding','8px 12px').style('font-size','11px').style('font-family','ui-monospace, monospace')
        .style('color','#f3f4f6').style('pointer-events','none')
        .style('opacity','0').style('max-width','300px').style('z-index','100')
    }

    // Dots
    const color = d3.scaleSequential(d3.interpolateCool).domain([0, facts.length - 1])
    const dotsG = root.append('g').attr('clip-path', 'url(#tl-clip)')

    dots = dotsG.selectAll<SVGCircleElement, FactInfo>('circle')
      .data(facts).enter().append('circle')
      .attr('cx', f => baseXScale(new Date(f.transaction_time * 1000)))
      .attr('cy', f => baseYScale(new Date((f.valid_time ?? f.transaction_time) * 1000)))
      .attr('r', 6)
      .attr('fill', (_, i) => color(i))
      .attr('stroke', '#0f172a').attr('stroke-width', 1.5)
      .attr('cursor', 'pointer')
      .on('mouseover', function(event, f) {
        d3.select(this).attr('r', 9).attr('stroke', '#60a5fa').attr('stroke-width', 2)
        const val = typeof f.value === 'object' ? JSON.stringify(f.value, null, 2) : String(f.value)
        const vt  = f.valid_time ? new Date(f.valid_time*1000).toLocaleString() : 'present'
        tooltip.html(`
          <div style="color:#60a5fa;margin-bottom:4px;font-weight:600">${f.id.slice(0,12)}���</div>
          <div style="color:#9ca3af">tx: ${new Date(f.transaction_time*1000).toLocaleString()}</div>
          <div style="color:#06b6d4">valid: ${vt}</div>
          ${f.causation ? `<div style="color:#6b7280;margin-top:2px">��� ${f.causation.slice(0,14)}</div>` : ''}
          <pre style="color:#fbbf24;margin-top:6px;font-size:10px;white-space:pre-wrap;max-height:80px;overflow:auto">${val.slice(0,200)}</pre>
        `)
          .style('opacity', '1')
          .style('left',  `${event.offsetX + 14}px`)
          .style('top',   `${event.offsetY - 14}px`)
      })
      .on('mousemove', function(event) {
        tooltip.style('left', `${event.offsetX + 14}px`).style('top', `${event.offsetY - 14}px`)
      })
      .on('mouseout', function() {
        d3.select(this).attr('r', 6).attr('stroke', '#0f172a').attr('stroke-width', 1.5)
        tooltip.style('opacity', '0')
      })

    // D3 Zoom
    zoomRef = d3.zoom<SVGSVGElement, unknown>()
      .scaleExtent([0.3, 40])
      .on('zoom', (event: d3.D3ZoomEvent<SVGSVGElement, unknown>) => {
        const newX = event.transform.rescaleX(baseXScale)
        const newY = event.transform.rescaleY(baseYScale)

        xAxisG.call(xAxis.scale(newX))
        yAxisG.call(yAxis.scale(newY))
        styleAxis(xAxisG); styleAxis(yAxisG)

        dots.attr('cx', f => newX(new Date(f.transaction_time * 1000)))
             .attr('cy', f => newY(new Date((f.valid_time ?? f.transaction_time) * 1000)))

        // Diagonal
        diagLine
          .attr('x1', newX(new Date(tMin))).attr('y1', newY(new Date(tMin)))
          .attr('x2', newX(new Date(tMax))).attr('y2', newY(new Date(tMax)))

        updateAsOf(newX)
      })

    d3.select(svgEl).call(zoomRef)
  }

  function updateAsOf(xScl: d3.ScaleTime<number, number>) {
    if (asOfTs === null || !asOfLine) return
    const x = xScl(new Date(asOfTs * 1000))
    asOfLine.attr('x1', x).attr('x2', x).style('display', null)
    asOfLabel.attr('x', x + 4).style('display', null)
  }

  function resetZoom() {
    if (!svgEl || !zoomRef) return
    d3.select(svgEl).transition().duration(350).call(zoomRef.transform, d3.zoomIdentity)
  }

  $: if (facts.length > 0 && svgEl && activeMode === 'bitemporal') render()

  let resizeObs: ResizeObserver
  let unlistenHistory: () => void

  onMount(async () => {
    resizeObs = new ResizeObserver(() => { if (facts.length > 0 && activeMode === 'bitemporal') render() })
    if (wrapper) resizeObs.observe(wrapper)
    loadPlaybackReceipt()
    loadTelemetryHistory()

    // Listen to backend telemetry history updates (TIVF-P14-9)
    try {
      unlistenHistory = await listen<RedactedTraceReceipt[]>('telemetry-history-updated', (event) => {
        historyReceipts = event.payload;
        if (selectedHistoryEntry) {
          selectedHistoryEntry = historyReceipts.find(r => r.receipt_id === selectedHistoryEntry?.receipt_id) || null;
        }
      });
    } catch (e) {
      console.error("Failed to subscribe to telemetry history event bridge:", e);
    }
  })
  onDestroy(() => {
    resizeObs?.disconnect();
    tooltip?.remove();
    if (unlistenHistory) {
      unlistenHistory();
    }
  })
</script>

<div class="flex flex-col gap-3 h-full">

  <!-- Mode Switcher -->
  <div class="flex border-b border-gray-800 shrink-0 mb-1">
    <button
      class="px-4 py-2 text-xs font-mono border-b-2 transition-colors {activeMode === 'bitemporal' ? 'border-yellow-500 text-yellow-500 font-bold' : 'border-transparent text-gray-400 hover:text-gray-200'}"
      on:click={() => activeMode = 'bitemporal'}
    >
      Bitemporal Facts Explorer
    </button>
    <button
      class="px-4 py-2 text-xs font-mono border-b-2 transition-colors {activeMode === 'playback' ? 'border-yellow-500 text-yellow-500 font-bold' : 'border-transparent text-gray-400 hover:text-gray-200'}"
      on:click={() => { activeMode = 'playback'; loadPlaybackReceipt(); }}
    >
      Trace Playback Inspector
    </button>
    <button
      class="px-4 py-2 text-xs font-mono border-b-2 transition-colors {activeMode === 'history' ? 'border-yellow-500 text-yellow-500 font-bold' : 'border-transparent text-gray-400 hover:text-gray-200'}"
      on:click={() => { activeMode = 'history'; loadTelemetryHistory(); }}
    >
      Telemetry History Viewer
    </button>
  </div>

  {#if activeMode === 'bitemporal'}
    <!-- Controls -->
    <div class="flex gap-2 items-end flex-wrap shrink-0">
      <div>
        <label class="block text-xs text-gray-400 mb-1 font-mono">Store</label>
        <input bind:value={store} placeholder="e.g. leads"
          class="bg-gray-900 border border-gray-700 rounded px-3 py-2 text-sm outline-none focus:border-blue-500 w-36 font-mono text-gray-200"/>
      </div>
      <div>
        <label class="block text-xs text-gray-400 mb-1 font-mono">Key <span class="text-gray-600">(opt)</span></label>
        <input bind:value={key} placeholder="all keys"
          class="bg-gray-900 border border-gray-700 rounded px-3 py-2 text-sm outline-none focus:border-blue-500 w-36 font-mono text-gray-200"/>
      </div>
      <button on:click={query} disabled={loading}
        class="px-4 py-2 bg-blue-600 hover:bg-blue-500 disabled:bg-gray-700 rounded text-sm font-semibold transition-colors text-white">
        {loading ? '��� Loading���' : 'Render'}
      </button>

      {#if facts.length > 0}
        <button on:click={resetZoom}
          class="px-3 py-2 bg-gray-800 hover:bg-gray-700 rounded text-sm transition-colors text-gray-300 font-mono"
          title="Reset zoom/pan">
          ��� Reset
        </button>
        <div class="text-xs text-gray-500 self-center font-mono">
          {facts.length} facts �� scroll to zoom �� drag to pan
        </div>
      {/if}
    </div>

    {#if error}
      <div class="text-red-400 text-sm bg-red-950/60 rounded p-2 shrink-0 border border-red-900 font-mono">��� {error}</div>
    {/if}

    <!-- Legend -->
    {#if facts.length > 0}
      <div class="flex gap-5 text-xs text-gray-500 shrink-0 flex-wrap font-mono">
        <span>��� fact (color = sequence)</span>
        <span class="text-yellow-500">- - as_of cursor</span>
        <span class="text-gray-600">- - - tx = valid</span>
      </div>
    {/if}

    <!-- Chart -->
    <div
      bind:this={wrapper}
      class="relative flex-1 min-h-0 bg-gray-900 rounded-lg border border-gray-800 overflow-hidden"
    >
      {#if facts.length === 0}
        <div class="absolute inset-0 flex flex-col items-center justify-center text-gray-600 gap-2 font-mono">
          <div class="text-3xl opacity-20">���</div>
          <div class="text-sm">Enter a store name and click Render to visualize bitemporal facts.</div>
        </div>
      {:else}
        <svg bind:this={svgEl} class="w-full h-full" style="min-height:380px"></svg>
      {/if}
    </div>
  {:else if activeMode === 'playback'}
    <!-- Playback Inspector Mode -->
    <div class="flex flex-col gap-3 h-full min-h-0 flex-1">
      <!-- Playback Controls/Header -->
      <div class="flex gap-2 justify-between items-center shrink-0 flex-wrap">
        <div class="flex gap-3 items-center">
          <button on:click={loadPlaybackReceipt}
            class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 rounded text-xs font-semibold text-gray-200 transition-colors font-mono">
            ��� Refresh Receipt
          </button>
          {#if playbackReceipt}
            <div class="text-xs text-gray-400 font-mono">
              ID: <span class="text-gray-300">{playbackReceipt.playback_id.slice(0, 8)}...</span>
              �� Time: <span class="text-gray-300">{new Date(playbackReceipt.timestamp).toLocaleString()}</span>
              �� Status:
              <span class="px-2 py-0.5 rounded text-[10px] font-bold {playbackReceipt.success ? 'bg-emerald-950/80 text-emerald-400 border border-emerald-800' : 'bg-red-950/80 text-red-400 border border-red-800'}">
                {playbackReceipt.success ? 'SUCCESS' : 'FAILED'}
              </span>
            </div>
          {/if}
        </div>
      </div>

      {#if playbackError}
        <div class="text-red-400 text-xs bg-red-950/60 border border-red-900 rounded p-3 shrink-0 font-mono">
          ��� {playbackError}
        </div>
      {/if}

      {#if playbackReceipt}
        <div class="flex flex-1 min-h-0 gap-4">
          <!-- Steps List (Left Column) -->
          <div class="w-1/2 flex flex-col bg-gray-950 border border-gray-800 rounded-lg overflow-hidden">
            <div class="px-3 py-2 bg-gray-900 border-b border-gray-800 text-xs font-mono text-gray-400 font-bold shrink-0">
              Playback Steps ({playbackReceipt.steps.length})
            </div>
            <div class="flex-1 overflow-y-auto p-2 space-y-1 bg-gray-950/50">
              {#each playbackReceipt.steps as step, idx}
                <button
                  class="w-full text-left p-3 rounded-lg border transition-all flex flex-col gap-1.5 {selectedStep === step ? 'bg-gray-900 border-yellow-500/50 shadow-md shadow-yellow-500/5' : 'bg-gray-950 border-gray-900 hover:border-gray-800'}"
                  on:click={() => handleSelectStep(step)}
                >
                  <div class="flex justify-between items-center w-full">
                    <span class="text-xs font-mono font-bold text-gray-400">Step #{idx + 1}</span>
                    <span class="px-1.5 py-0.5 rounded text-[9px] font-bold font-mono {step.success ? 'bg-emerald-950/50 text-emerald-400' : 'bg-red-950/50 text-red-400'}">
                      {step.success ? 'OK' : 'ERR'}
                    </span>
                  </div>
                  <div class="text-xs font-mono text-gray-200 truncate">{step.view_id}</div>
                  {#if step.source_receipt_id}
                    <div class="text-[10px] font-mono text-gray-500">Source ID: {step.source_receipt_id}</div>
                  {/if}
                </button>
              {/each}
            </div>
          </div>

          <!-- Step Detail Panel (Right Column) -->
          <div class="w-1/2 flex flex-col bg-gray-950 border border-gray-800 rounded-lg overflow-hidden">
            <div class="px-3 py-2 bg-gray-900 border-b border-gray-800 text-xs font-mono text-gray-400 font-bold shrink-0">
              Step Details
            </div>
            <div class="flex-1 overflow-y-auto p-4 space-y-4 bg-gray-950/30">
              {#if selectedStep}
                <div class="space-y-4">
                  <div>
                    <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">View ID</div>
                    <div class="text-xs font-mono text-gray-200 bg-gray-900 px-2.5 py-2 rounded border border-gray-800 mt-1">{selectedStep.view_id}</div>
                  </div>

                  <div>
                    <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Status</div>
                    <div class="text-xs font-mono font-bold mt-1.5">
                      <span class="px-2 py-1 rounded {selectedStep.success ? 'bg-emerald-950/80 text-emerald-400 border border-emerald-800' : 'bg-red-950/80 text-red-400 border border-red-800'}">
                        {selectedStep.success ? 'SUCCESS' : 'FAILED'}
                      </span>
                    </div>
                    {#if !selectedStep.success}
                      <div class="text-xs font-mono text-red-400 mt-2 bg-red-950/30 p-2.5 rounded border border-red-950">{selectedStep.message}</div>
                    {/if}
                  </div>

                  {#if selectedStep.source_receipt_id}
                    <div>
                      <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Source Receipt ID</div>
                      <div class="text-xs font-mono text-gray-300 bg-gray-900 px-2.5 py-2 rounded border border-gray-800 mt-1">{selectedStep.source_receipt_id}</div>
                    </div>
                  {/if}

                  <div>
                    <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Receipt ID</div>
                    <div class="text-xs font-mono text-gray-400 bg-gray-900 px-2.5 py-2 rounded border border-gray-800 mt-1">{selectedStep.receipt_id}</div>
                  </div>

                  <div>
                    <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Timestamp</div>
                    <div class="text-xs font-mono text-gray-300 bg-gray-900 px-2.5 py-2 rounded border border-gray-800 mt-1">{selectedStep.timestamp}</div>
                  </div>

                  <div>
                    <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Accepted Keys</div>
                    {#if selectedStep.accepted_keys && selectedStep.accepted_keys.length > 0}
                      <div class="flex flex-wrap gap-1.5 mt-1.5">
                        {#each selectedStep.accepted_keys as key}
                          <span class="px-2 py-1 bg-emerald-950/30 border border-emerald-900/50 text-emerald-400 rounded text-[10px] font-mono">{key}</span>
                        {/each}
                      </div>
                    {:else}
                      <div class="text-xs text-gray-500 italic mt-1 font-mono">None</div>
                    {/if}
                  </div>

                  <div>
                    <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Rejected Keys</div>
                    {#if selectedStep.rejected_keys && selectedStep.rejected_keys.length > 0}
                      <div class="flex flex-wrap gap-1.5 mt-1.5">
                        {#each selectedStep.rejected_keys as key}
                          <span class="px-2 py-1 bg-red-950/30 border border-red-900/50 text-red-400 rounded text-[10px] font-mono">{key}</span>
                        {/each}
                      </div>
                    {:else}
                      <div class="text-xs text-gray-500 italic mt-1 font-mono">None</div>
                    {/if}
                  </div>
                </div>
              {:else}
                <div class="text-center py-16 text-gray-600 text-xs font-mono">
                  Select a playback step to inspect details
                </div>
              {/if}
            </div>
          </div>
        </div>
      {/if}
    </div>
  {:else if activeMode === 'history'}
    <!-- Telemetry History Mode -->
    <div class="flex flex-col gap-3 h-full min-h-0 flex-1">
      <div class="flex gap-2 justify-between items-center shrink-0 flex-wrap">
        <div class="flex gap-3 items-center">
          <button on:click={loadTelemetryHistory} disabled={loadingHistory}
            class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 disabled:bg-gray-900 rounded text-xs font-semibold text-gray-200 transition-colors font-mono">
            {loadingHistory ? '��� Refreshing���' : '��� Refresh History'}
          </button>
          <div class="text-xs text-gray-400 font-mono">
            Status: <span class="text-gray-300">read-only telemetry buffer (capacity: 10, FIFO eviction)</span>
          </div>
        </div>
      </div>

      {#if historyError}
        <div class="text-red-400 text-xs bg-red-950/60 border border-red-900 rounded p-3 shrink-0 font-mono">
          ��� {historyError}
        </div>
      {/if}

      <div class="flex flex-1 min-h-0 gap-4">
        <!-- History List (Left Column) -->
        <div class="w-1/2 flex flex-col bg-gray-950 border border-gray-800 rounded-lg overflow-hidden">
          <div class="px-3 py-2 bg-gray-900 border-b border-gray-800 text-xs font-mono text-gray-400 font-bold shrink-0">
            History Entries ({historyReceipts.length})
          </div>
          <div class="flex-1 overflow-y-auto p-2 space-y-1 bg-gray-950/50">
            {#if historyReceipts.length === 0}
              <div class="text-center py-16 text-gray-600 text-xs font-mono">
                No telemetry history entries found. Run VM trace or playback first.
              </div>
            {:else}
              {#each historyReceipts as entry, idx}
                <button
                  class="w-full text-left p-3 rounded-lg border transition-all flex flex-col gap-1.5 {selectedHistoryEntry === entry ? 'bg-gray-900 border-yellow-500/50 shadow-md shadow-yellow-500/5' : 'bg-gray-950 border-gray-900 hover:border-gray-800'}"
                  on:click={() => handleSelectHistoryEntry(entry)}
                >
                  <div class="flex justify-between items-center w-full">
                    <span class="text-xs font-mono font-bold text-gray-400">Entry #{idx + 1}</span>
                    <span class="px-1.5 py-0.5 rounded text-[9px] font-bold font-mono {entry.event_type === 'applied_trace_events' ? 'bg-emerald-950/50 text-emerald-400' : 'bg-amber-950/50 text-amber-400'}">
                      {entry.event_type === 'applied_trace_events' ? 'APPLIED' : 'ATTEMPTED'}
                    </span>
                  </div>
                  <div class="text-xs font-mono text-gray-200 truncate">{entry.contract_id}</div>
                  <div class="text-[10px] font-mono text-gray-500">Trace: {entry.trace_id.slice(0, 16)}...</div>
                </button>
              {/each}
            {/if}
          </div>
        </div>

        <!-- History Detail Panel (Right Column) -->
        <div class="w-1/2 flex flex-col bg-gray-950 border border-gray-800 rounded-lg overflow-hidden">
          <div class="px-3 py-2 bg-gray-900 border-b border-gray-800 text-xs font-mono text-gray-400 font-bold shrink-0">
            Telemetry Details
          </div>
          <div class="flex-1 overflow-y-auto p-4 space-y-4 bg-gray-950/30">
            {#if selectedHistoryEntry}
              <div class="space-y-4">
                <div>
                  <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Trace ID</div>
                  <div class="text-xs font-mono text-gray-200 bg-gray-900 px-2.5 py-2 rounded border border-gray-800 mt-1">{selectedHistoryEntry.trace_id}</div>
                </div>

                <div>
                  <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Contract ID</div>
                  <div class="text-xs font-mono text-gray-200 bg-gray-900 px-2.5 py-2 rounded border border-gray-800 mt-1">{selectedHistoryEntry.contract_id}</div>
                </div>

                <div>
                  <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Event Classification</div>
                  <div class="text-xs font-mono font-bold mt-1.5">
                    <span class="px-2 py-1 rounded {selectedHistoryEntry.event_type === 'applied_trace_events' ? 'bg-emerald-950/80 text-emerald-400 border border-emerald-800' : 'bg-amber-950/80 text-amber-400 border border-amber-800'}">
                      {selectedHistoryEntry.event_type}
                    </span>
                  </div>
                </div>

                <div>
                  <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Status</div>
                  <div class="text-xs font-mono text-gray-300 bg-gray-900 px-2.5 py-2 rounded border border-gray-800 mt-1">{selectedHistoryEntry.status}</div>
                </div>

                {#if selectedHistoryEntry.receipt_id}
                  <div>
                    <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Receipt ID</div>
                    <div class="text-xs font-mono text-gray-300 bg-gray-900 px-2.5 py-2 rounded border border-gray-800 mt-1">{selectedHistoryEntry.receipt_id}</div>
                  </div>
                {/if}

                <div>
                  <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Timestamp</div>
                  <div class="text-xs font-mono text-gray-300 bg-gray-900 px-2.5 py-2 rounded border border-gray-800 mt-1">{selectedHistoryEntry.timestamp}</div>
                </div>

                <div>
                  <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Redaction Policy</div>
                  <div class="text-xs font-mono text-gray-400 bg-gray-900 px-2.5 py-2 rounded border border-gray-800 mt-1">{selectedHistoryEntry.redaction_policy}</div>
                </div>

                <div>
                  <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Outputs Digest</div>
                  <div class="text-[11px] font-mono text-gray-400 bg-gray-900/50 px-2.5 py-2 rounded border border-gray-900 mt-1 break-all">{selectedHistoryEntry.outputs_digest}</div>
                </div>

                <div>
                  <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Diagnostics Digest</div>
                  <div class="text-[11px] font-mono text-gray-400 bg-gray-900/50 px-2.5 py-2 rounded border border-gray-900 mt-1 break-all">{selectedHistoryEntry.diagnostics_digest}</div>
                </div>

                <div>
                  <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Target Views</div>
                  {#if selectedHistoryEntry.target_views && selectedHistoryEntry.target_views.length > 0}
                    <div class="flex flex-wrap gap-1.5 mt-1.5">
                      {#each selectedHistoryEntry.target_views as target}
                        <span class="px-2 py-1 bg-gray-900 border border-gray-800 text-gray-300 rounded text-[10px] font-mono">{target}</span>
                      {/each}
                    </div>
                  {:else}
                    <div class="text-xs text-gray-500 italic mt-1 font-mono">None</div>
                  {/if}
                </div>

                <div>
                  <div class="text-[10px] uppercase tracking-wider text-gray-500 font-mono font-bold">Selected Slot Keys</div>
                  {#if selectedHistoryEntry.selected_slot_keys && selectedHistoryEntry.selected_slot_keys.length > 0}
                    <div class="flex flex-wrap gap-1.5 mt-1.5">
                      {#each selectedHistoryEntry.selected_slot_keys as key}
                        <span class="px-2 py-1 bg-blue-950/30 border border-blue-900/50 text-blue-400 rounded text-[10px] font-mono">{key}</span>
                      {/each}
                    </div>
                  {:else}
                    <div class="text-xs text-gray-500 italic mt-1 font-mono">None</div>
                  {/if}
                </div>
              </div>
            {:else}
              <div class="text-center py-16 text-gray-600 text-xs font-mono">
                Select a history entry to inspect details
              </div>
            {/if}
          </div>
        </div>
      </div>
    </div>
  {/if}

</div>
