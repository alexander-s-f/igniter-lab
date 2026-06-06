<script lang="ts">
  import { tick, onDestroy } from 'svelte'
  import { Network } from 'vis-network'
  import { DataSet } from 'vis-data'
  import { api } from '$lib/api'
  import type { ContractInfo } from '$lib/types'

  export let contracts: ContractInfo[] = []
  export let preselected: string = ''

  let selected = ''
  let container: HTMLDivElement
  let network: Network | null = null
  let error = ''
  let loading = false
  let selectedNode: any = null
  let nodeCount = 0
  let rawIr: any = null
  let showRaw = false

  // ������ Node styling by kind ������������������������������������������������������������������������������������������������������������������������������������������������������������������
  const NODE_STYLE: Record<string, { color: string; shape: string; font: string }> = {
    input:        { color: '#1d4ed8', shape: 'box',      font: '#bfdbfe' },
    output:       { color: '#7c3aed', shape: 'box',      font: '#ddd6fe' },
    compute:      { color: '#065f46', shape: 'ellipse',  font: '#6ee7b7' },
    read:         { color: '#92400e', shape: 'diamond',  font: '#fde68a' },
    loop:         { color: '#1e3a5f', shape: 'hexagon',  font: '#93c5fd' },
    service_loop: { color: '#0f4c75', shape: 'hexagon',  font: '#7dd3fc' },
    invariant:    { color: '#7f1d1d', shape: 'triangle', font: '#fca5a5' },
    snapshot:     { color: '#3730a3', shape: 'ellipse',  font: '#c7d2fe' },
    window:       { color: '#065f46', shape: 'dot',      font: '#6ee7b7' },
    fold_stream:  { color: '#1a365d', shape: 'dot',      font: '#90cdf4' },
  }

  const FRAGMENT_BORDER: Record<string, string> = {
    core: '#22c55e', escape: '#eab308', temporal: '#06b6d4',
    oof: '#ef4444', unknown: '#6b7280',
  }

  // ������ Graph builder ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  // IR structure (actual igniter_machine format):
  //   input_ports:    [{name, type_tag, lifecycle, required}]
  //   compute_nodes:  [{name, kind, node_id, type_tag, fragment_class, dependencies: ["input:x",...], lifecycle}]
  //   output_ports:   [{name, type_tag, lifecycle, required}]
  //   fragment_class, modifier, name, contract_id ���
  function buildGraph(ir: any) {
    const nodes: any[] = []
    const edges: any[] = []
    const nodeIds = new Set<string>()

    const fragClass  = ir.fragment_class ?? ir.modifier ?? 'unknown'
    const rootBorder = FRAGMENT_BORDER[fragClass] ?? '#6b7280'

    function addNode(id: string, label: string, kind: string, tooltip: string, frag?: string) {
      if (nodeIds.has(id)) return
      nodeIds.add(id)
      const style = NODE_STYLE[kind] ?? { color: '#374151', shape: 'box', font: '#d1d5db' }
      const bc = FRAGMENT_BORDER[frag ?? fragClass] ?? rootBorder
      nodes.push({
        id,
        label,
        shape: style.shape,
        color: {
          background: style.color,
          border: bc,
          highlight: { background: style.color, border: '#60a5fa' },
          hover:      { background: style.color, border: '#93c5fd' },
        },
        font: { color: style.font, size: 12, face: 'monospace' },
        title: tooltip,
        borderWidth: 2,
        margin: { top: 6, right: 10, bottom: 6, left: 10 },
      })
    }

    function addEdge(from: string, to: string) {
      if (!from || !to || from === to) return
      if (edges.some(e => e.from === from && e.to === to)) return
      edges.push({
        from, to,
        arrows: { to: { enabled: true, scaleFactor: 0.7 } },
        color: { color: '#374151', highlight: '#60a5fa', hover: '#60a5fa' },
        smooth: { type: 'cubicBezier', forceDirection: 'horizontal' },
      })
    }

    // Resolve a bare name (e.g. "greeting") to its nodeId
    const RESOLVE_KINDS = ['compute', 'read', 'loop', 'fold_stream', 'snapshot', 'window', 'input']
    function resolveByName(name: string): string | undefined {
      return RESOLVE_KINDS.map(k => `${k}:${name}`).find(id => nodeIds.has(id))
    }

    // 1. Input ports
    for (const inp of ir.input_ports ?? ir.inputs ?? []) {
      addNode(
        `input:${inp.name}`,
        `in\n${inp.name}`,
        'input',
        `<b>input</b>: ${inp.name}<br/>type: ${inp.type_tag ?? inp.type?.name ?? '?'}<br/>lifecycle: ${inp.lifecycle ?? 'local'}`,
      )
    }

    // 2. Compute nodes ��� dependencies already carry "kind:name" prefix
    for (const node of ir.compute_nodes ?? ir.nodes ?? []) {
      const kind = node.kind ?? 'compute'
      const id   = `${kind}:${node.name}`
      const frag = node.fragment_class ?? node.fragment ?? fragClass
      const deps = node.dependencies ?? node.deps ?? []
      addNode(
        id,
        `${kind}\n${node.name}`,
        kind,
        `<b>${kind}</b>: ${node.name}<br/>type: ${node.type_tag ?? '?'}<br/>deps: ${deps.join(', ') || 'none'}`,
        frag,
      )
      // dependencies are already "input:x" / "compute:y" format
      for (const dep of deps) {
        // if dep has a known prefix, use directly; otherwise resolve by name
        const depId = dep.includes(':') ? dep : resolveByName(dep) ?? `input:${dep}`
        addEdge(depId, id)
      }
    }

    // 3. Output ports ��� connect to matching compute/read/input node by name
    for (const out of ir.output_ports ?? ir.outputs ?? []) {
      const outId = `output:${out.name}`
      addNode(
        outId,
        `out\n${out.name}`,
        'output',
        `<b>output</b>: ${out.name}<br/>type: ${out.type_tag ?? out.type?.name ?? '?'}`,
      )
      const srcId = resolveByName(out.name)
      if (srcId) addEdge(srcId, outId)
    }

    return { nodes, edges }
  }

  // ������ Render ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  async function render() {
    if (!selected) return
    // Wait a tick for container to be bound after reactive select change
    await tick()
    if (!container) return

    error = ''; loading = true; selectedNode = null; rawIr = null

    try {
      const ir = await api.getContractIr(selected)
      rawIr = ir
      console.log('[DAG] IR for', selected, JSON.stringify(ir, null, 2))

      const { nodes, edges } = buildGraph(ir)
      nodeCount = nodes.length

      if (network) { network.destroy(); network = null }

      if (nodes.length === 0) {
        error = `No nodes found in IR for "${selected}". Check raw IR below.`
        return
      }

      const nodesDS = new DataSet(nodes)
      const edgesDS = new DataSet(edges)

      network = new Network(
        container,
        { nodes: nodesDS, edges: edgesDS },
        {
          layout: {
            hierarchical: {
              enabled: true,
              direction: 'LR',
              sortMethod: 'directed',
              levelSeparation: 200,
              nodeSpacing: 100,
              treeSpacing: 80,
            },
          },
          physics: { enabled: false },
          interaction: { hover: true, tooltipDelay: 100, navigationButtons: false },
          nodes:  { borderWidth: 2 },
          edges:  { width: 1.5 },
        },
      )

      // Fit all nodes into view after layout
      network.once('afterDrawing', () => network?.fit({ animation: false }))

      network.on('click', (params) => {
        if (params.nodes.length > 0) {
          const nodeId = params.nodes[0]
          selectedNode = nodesDS.get(nodeId) as any
        } else {
          selectedNode = null
        }
      })
    } catch (e) {
      error = String(e)
    } finally {
      loading = false
    }
  }

  // Reactive: re-render when selected changes (and container is bound)
  $: if (selected) render()

  // Reactive: apply preselected
  $: if (preselected && preselected !== selected) selected = preselected

  // ������ Layout direction ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let layoutDir: 'LR' | 'UD' | 'TB' = 'LR'

  function applyLayout(dir: 'LR' | 'UD' | 'TB') {
    layoutDir = dir
    if (network) {
      network.setOptions({
        layout: {
          hierarchical: {
            direction: dir,
          },
        },
      })
      network.stabilize()
      setTimeout(() => network?.fit({ animation: true }), 300)
    }
  }

  function fitGraph()  { network?.fit({ animation: true }) }
  function zoomIn()    { if (!network) return; const s = network.getScale(); network.moveTo({ scale: s * 1.3, animation: true }) }
  function zoomOut()   { if (!network) return; const s = network.getScale(); network.moveTo({ scale: s / 1.3, animation: true }) }

  onDestroy(() => { network?.destroy() })
</script>

<div class="flex gap-3 h-full min-h-0 overflow-hidden">

  <!-- Left: controls + legend + node detail -->
  <div class="w-52 shrink-0 flex flex-col gap-3 overflow-y-auto">

    <!-- Contract selector -->
    <div>
      <label class="block text-xs text-gray-400 mb-1" for="dag-select">Contract</label>
      <select id="dag-select" bind:value={selected}
        class="w-full bg-gray-900 border border-gray-700 rounded px-2 py-1.5 text-sm
               outline-none focus:border-blue-500 text-gray-200">
        <option value="">��� select ���</option>
        {#each contracts as c}
          <option value={c.name}>{c.name}</option>
        {/each}
      </select>
    </div>

    <!-- Status -->
    {#if loading}
      <div class="text-xs text-blue-400 flex items-center gap-2">
        <span class="animate-spin">���</span> Loading���
      </div>
    {:else if selected && !error}
      <div class="text-xs text-gray-500">{nodeCount} nodes</div>
    {/if}

    <!-- Legend: node types -->
    <div class="text-xs space-y-1 text-gray-500">
      <div class="font-semibold text-gray-400 mb-1">Node types</div>
      {#each [['input','#1d4ed8'],['output','#7c3aed'],['compute','#065f46'],['read','#92400e'],['loop','#1e3a5f'],['invariant','#7f1d1d']] as [k, c]}
        <div class="flex items-center gap-2">
          <span class="w-3 h-3 rounded-sm inline-block" style="background:{c}"></span>
          <span>{k}</span>
        </div>
      {/each}

      <div class="pt-2 font-semibold text-gray-400">Fragment class</div>
      {#each [['core','#22c55e'],['escape','#eab308'],['temporal','#06b6d4'],['oof','#ef4444']] as [k, c]}
        <div class="flex items-center gap-2">
          <span class="w-3 h-3 rounded-full inline-block border-2"
                style="border-color:{c};background:transparent"></span>
          <span>{k}</span>
        </div>
      {/each}
    </div>

    <!-- Selected node detail -->
    {#if selectedNode}
      <div class="bg-gray-900 border border-gray-700 rounded p-2 text-xs space-y-1">
        <div class="text-blue-400 font-semibold break-all">{selectedNode.id}</div>
        <div class="text-gray-400 leading-relaxed">{@html selectedNode.title ?? ''}</div>
      </div>
    {/if}
  </div>

  <!-- Right: graph canvas -->
  <div class="flex-1 min-w-0 flex flex-col overflow-hidden">

    <!-- Toolbar -->
    {#if selected && !error}
      <div class="flex items-center gap-1 px-2 py-1.5 border-b border-gray-800 shrink-0 bg-gray-900/50">
        <!-- Fit / zoom -->
        <button on:click={fitGraph}
          title="Fit all nodes"
          class="px-2 py-0.5 text-xs bg-gray-800 hover:bg-gray-700 rounded transition-colors text-gray-300">
          ��� Fit
        </button>
        <button on:click={zoomIn}
          title="Zoom in"
          class="w-6 h-6 flex items-center justify-center text-xs bg-gray-800 hover:bg-gray-700 rounded transition-colors text-gray-300">
          +
        </button>
        <button on:click={zoomOut}
          title="Zoom out"
          class="w-6 h-6 flex items-center justify-center text-xs bg-gray-800 hover:bg-gray-700 rounded transition-colors text-gray-300">
          ���
        </button>

        <div class="w-px h-4 bg-gray-700 mx-1"></div>

        <!-- Layout direction -->
        <span class="text-[10px] text-gray-600 mr-0.5">Layout</span>
        {#each [['LR','���'],['UD','���'],['TB','���']] as [dir, icon]}
          <button
            on:click={() => applyLayout(dir as 'LR' | 'UD' | 'TB')}
            title="Direction: {dir}"
            class="px-1.5 py-0.5 text-xs rounded transition-colors
                   {layoutDir === dir
                     ? 'bg-blue-700 text-white'
                     : 'bg-gray-800 hover:bg-gray-700 text-gray-400'}">
            {icon}
          </button>
        {/each}

        <div class="flex-1"></div>
        <span class="text-[10px] text-gray-600">{nodeCount} nodes</span>
      </div>
    {/if}

    <!-- Canvas -->
    <div class="flex-1 relative min-h-0">
      {#if error}
        <div class="absolute inset-0 flex flex-col overflow-auto p-4 gap-3">
          <div class="text-red-400 text-sm bg-red-950 rounded-lg p-4 text-center shrink-0">
            <div class="font-semibold mb-1">Error</div>
            <div class="text-xs opacity-80">{error}</div>
          </div>
          {#if rawIr}
            <div class="shrink-0">
              <button
                on:click={() => showRaw = !showRaw}
                class="text-xs text-gray-500 hover:text-gray-300 flex items-center gap-1">
                {showRaw ? '���' : '���'} Raw IR (top-level keys: [{Object.keys(rawIr).join(', ')}])
              </button>
              {#if showRaw}
                <pre class="mt-2 text-xs text-gray-400 bg-gray-900 rounded p-3 overflow-auto max-h-96 leading-relaxed">{JSON.stringify(rawIr, null, 2)}</pre>
              {/if}
            </div>
          {/if}
        </div>
      {:else if !selected}
        <div class="absolute inset-0 flex items-center justify-center text-gray-600 text-sm">
          Select a contract to visualize its dependency graph.
        </div>
      {:else}
        <div
          bind:this={container}
          class="absolute inset-0 bg-gray-900 rounded-lg border border-gray-800"
        ></div>
      {/if}
    </div>
  </div>
</div>
