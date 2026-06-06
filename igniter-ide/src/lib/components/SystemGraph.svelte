<script lang="ts">
  import { onMount, onDestroy, createEventDispatcher } from 'svelte'
  import { Network } from 'vis-network'
  import { DataSet } from 'vis-data'
  import { api } from '$lib/api'

  const dispatch = createEventDispatcher<{ drillDown: string }>()

  let container: HTMLDivElement
  let network: Network | null = null
  let loading = false
  let error = ''
  let nodeCount = 0
  let edgeCount = 0
  let selectedInfo: any = null

  const FRAGMENT_COLORS: Record<string, { bg: string; border: string; font: string }> = {
    core:     { bg: '#065f46', border: '#22c55e', font: '#6ee7b7' },
    escape:   { bg: '#78350f', border: '#eab308', font: '#fde68a' },
    temporal: { bg: '#0c4a6e', border: '#06b6d4', font: '#7dd3fc' },
    oof:      { bg: '#7f1d1d', border: '#ef4444', font: '#fca5a5' },
    unknown:  { bg: '#1f2937', border: '#6b7280', font: '#9ca3af' },
  }

  async function load() {
    loading = true; error = ''
    try {
      const graph = await api.getSystemGraph()
      nodeCount = graph.nodes.length
      edgeCount = graph.edges.length
      renderGraph(graph)
    } catch(e) { error = String(e) }
    finally { loading = false }
  }

  function renderGraph(graph: any) {
    if (!container) return
    if (network) { network.destroy(); network = null }

    const colors = FRAGMENT_COLORS
    const vNodes = new DataSet(graph.nodes.map((n: any) => {
      const c = colors[n.fragment_class] ?? colors.unknown
      const inputNames = n.inputs.map((s: string) => s.split(':')[0]).join(', ')
      const outputNames = n.outputs.map((s: string) => s.split(':')[0]).join(', ')
      return {
        id: n.id,
        label: `${n.contract_name}\n[${n.fragment_class}]\n${n.node_count} nodes`,
        color: { background: c.bg, border: c.border, highlight: { background: c.bg, border: '#60a5fa' } },
        font: { color: c.font, size: 12, face: 'monospace', multi: true },
        shape: 'box',
        borderWidth: 2,
        margin: 10,
        title: `<b>${n.contract_name}</b><br/>Fragment: ${n.fragment_class}<br/>Inputs: ${inputNames || '���'}<br/>Outputs: ${outputNames || '���'}<br/>Nodes: ${n.node_count}<br/><i>Double-click to inspect</i>`,
      }
    }))

    const vEdges = new DataSet(graph.edges.map((e: any, i: number) => ({
      id: `e${i}`,
      from: e.from, to: e.to,
      label: e.label,
      arrows: { to: { enabled: true, scaleFactor: 0.8 } },
      color: { color: '#374151', highlight: '#60a5fa' },
      font: { size: 10, color: '#9ca3af', background: '#111827' },
      smooth: { type: 'cubicBezier', roundness: 0.4 },
      width: 1.5,
      dashes: false,
    })))

    network = new Network(container, { nodes: vNodes as any, edges: vEdges as any }, {
      layout: { hierarchical: { enabled: false } },
      physics: {
        enabled: true,
        solver: 'forceAtlas2Based',
        forceAtlas2Based: { gravitationalConstant: -60, springLength: 200, springConstant: 0.05, damping: 0.9 },
        stabilization: { iterations: 150 },
      },
      interaction: { hover: true, tooltipDelay: 80 },
      nodes: { borderWidth: 2, shadow: { enabled: true, color: 'rgba(0,0,0,0.5)', size: 8 } },
      edges: { shadow: false },
    })

    network.on('click', (p) => {
      if (p.nodes.length > 0) {
        const n = vNodes.get(p.nodes[0]) as any
        selectedInfo = n
      } else { selectedInfo = null }
    })

    network.on('doubleClick', (p) => {
      if (p.nodes.length > 0) {
        dispatch('drillDown', p.nodes[0] as string)
      }
    })

    network.once('stabilizationIterationsDone', () => {
      network?.fit({ animation: { duration: 800, easingFunction: 'easeInOutQuad' } })
    })
  }

  onMount(load)
  onDestroy(() => { if (network) network.destroy() })
</script>

<div class="h-full flex flex-col gap-3">
  <!-- Toolbar -->
  <div class="flex items-center gap-3 flex-wrap">
    <button on:click={load} disabled={loading}
      class="px-3 py-1.5 bg-blue-700 hover:bg-blue-600 disabled:bg-gray-700 rounded text-sm font-semibold transition-colors">
      {loading ? '... Loading' : 'Refresh'}
    </button>
    <span class="text-xs text-gray-500">{nodeCount} contracts �� {edgeCount} connections</span>
    {#if nodeCount > 0}
      <span class="text-xs text-gray-600">Double-click a contract to inspect its internal DAG</span>
    {/if}
    <!-- Legend -->
    <div class="ml-auto flex gap-3 text-xs">
      {#each [['core','#22c55e'],['escape','#eab308'],['temporal','#06b6d4'],['oof','#ef4444']] as [k,c]}
        <span class="flex items-center gap-1">
          <span class="w-2.5 h-2.5 rounded-sm inline-block border-2" style="border-color:{c};background:transparent"></span>
          {k}
        </span>
      {/each}
    </div>
  </div>

  {#if error}
    <div class="text-red-400 text-sm">x {error}</div>
  {/if}

  <div class="flex gap-3 flex-1" style="min-height: 500px">
    <!-- Graph -->
    <div bind:this={container}
      class="flex-1 bg-gray-900 rounded-lg border border-gray-800"
      style="min-height: 480px">
      {#if nodeCount === 0 && !loading}
        <div class="flex flex-col items-center justify-center h-full text-gray-600 gap-2">
          <span class="text-4xl">���</span>
          <span class="text-sm">No contracts loaded.</span>
          <span class="text-xs">Load contracts from the workspace to see the system graph.</span>
        </div>
      {/if}
    </div>

    <!-- Selection info -->
    {#if selectedInfo}
      <div class="w-52 bg-gray-900 border border-gray-800 rounded-lg p-3 text-xs space-y-2 shrink-0">
        <div class="font-bold text-blue-400">{selectedInfo.id}</div>
        <div class="text-gray-400 whitespace-pre-line leading-relaxed">{@html (selectedInfo.title ?? '').replace(/<br\/>/g,'\n').replace(/<[^>]+>/g,'')}</div>
        <button
          on:click={() => dispatch('drillDown', selectedInfo.id)}
          class="w-full px-2 py-1.5 bg-blue-800 hover:bg-blue-700 rounded text-xs text-blue-200 transition-colors">
          Inspect internal DAG
        </button>
      </div>
    {/if}
  </div>
</div>
