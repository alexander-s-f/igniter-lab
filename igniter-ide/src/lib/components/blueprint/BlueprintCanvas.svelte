<!--
  BlueprintCanvas.svelte ��� Pan/zoom canvas host.

  Responsibilities:
    ��� Pan (drag background)  ��� transform translate
    ��� Zoom (wheel)           ��� transform scale
    ��� Render nodes (HTML divs) and edges (SVG overlay)
    ��� Forward node events (drag, select, port, gotosource)
    ��� Port drag ��� ghost edge ��� emit 'edgeCreated'

  The canvas uses a hybrid approach:
    - Outer div: clip / event capture
    - Inner transform div: pan + zoom
    - SVG layer inside transform: edges + ghost edge
    - HTML node divs inside transform: absolute positioned
-->
<script lang="ts">
  import { createEventDispatcher, onMount } from 'svelte'
  import type { BpGraph, BpNode as IrBpNode, BpEdge as IrBpEdge } from '$lib/blueprint/ir'
  import { HEADER_H, PORT_ROW_H } from '$lib/blueprint/ir'
  import BpNodeCard  from './BpNode.svelte'
  import BpEdgeLine  from './BpEdge.svelte'

  export let graph: BpGraph
  export let selectedNodeId: string | null = null
  export let inputValues: Record<string, string> = {}
  export let evaluatedValues: Record<string, string> = {}
  export let nodeErrors: Record<string, string> = {}

  const dispatch = createEventDispatcher<{
    nodeSelect:   string
    nodeDrag:     { id: string; x: number; y: number }
    edgeCreated:  { fromNodeId: string; fromPort: string; toNodeId: string; toPort: string }
    gotoSource:   number
    contextMenu:  { x: number; y: number; nodeId: string | null }
    inputValueChange: { name: string; value: string }
  }>()

  // ������ Pan / Zoom state ������������������������������������������������������������������������������������������������������������������������������������������������������������������

  let panX = 40
  let panY = 40
  let zoom = 1
  const ZOOM_MIN = 0.2
  const ZOOM_MAX = 2.5

  // ������ Node position overrides (drag moves without mutating graph) ���������������������������������

  let posOverrides = new Map<string, { x: number; y: number }>()

  // Reset overrides when graph changes (new parse)
  $: { graph; posOverrides = new Map() }

  function nodePos(n: IrBpNode): { x: number; y: number } {
    return posOverrides.get(n.id) ?? { x: n.x, y: n.y }
  }

  // ������ Canvas element ref ������������������������������������������������������������������������������������������������������������������������������������������������������������

  let container: HTMLDivElement
  let canvasW = 0
  let canvasH = 0

  onMount(() => {
    const ro = new ResizeObserver(e => {
      canvasW = e[0].contentRect.width
      canvasH = e[0].contentRect.height
    })
    ro.observe(container)
    return () => ro.disconnect()
  })

  // ������ Pan drag ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

  let panning = false
  let panStart = { x: 0, y: 0 }

  function onBackgroundMouseDown(e: MouseEvent) {
    if (e.button !== 0) return
    panning = true
    panStart = { x: e.clientX - panX, y: e.clientY - panY }
    e.preventDefault()

    const onMove = (me: MouseEvent) => {
      if (!panning) return
      panX = me.clientX - panStart.x
      panY = me.clientY - panStart.y
    }

    const onUp = () => {
      panning = false
      window.removeEventListener('mousemove', onMove)
      window.removeEventListener('mouseup', onUp)
    }

    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup', onUp)
  }

  function onMouseMove(e: MouseEvent) {
    if (portDrag) {
      ghostX2 = (e.clientX - container.getBoundingClientRect().left - panX) / zoom
      ghostY2 = (e.clientY - container.getBoundingClientRect().top  - panY) / zoom
    }
  }

  function onMouseUp() {
    if (portDrag) { portDrag = null }
  }

  function onWheel(e: WheelEvent) {
    e.preventDefault()
    const rect = container.getBoundingClientRect()
    const cx = e.clientX - rect.left
    const cy = e.clientY - rect.top
    const factor = e.deltaY < 0 ? 1.12 : 1 / 1.12
    const newZoom = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, zoom * factor))
    // Zoom toward cursor
    panX = cx - (cx - panX) * (newZoom / zoom)
    panY = cy - (cy - panY) * (newZoom / zoom)
    zoom = newZoom
  }

  // ������ Reset view ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

  export function resetView() {
    panX = 40; panY = 40; zoom = 1
  }

  export function fitView() {
    if (allNodes.length === 0) return
    const xs = allNodes.map(n => nodePos(n).x)
    const ys = allNodes.map(n => nodePos(n).y)
    const minX = Math.min(...xs)
    const minY = Math.min(...ys)
    const maxX = Math.max(...allNodes.map(n => nodePos(n).x + n.width))
    const maxY = Math.max(...allNodes.map(n => nodePos(n).y + n.height))
    const graphW = maxX - minX
    const graphH = maxY - minY
    zoom = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, 0.85 * Math.min(canvasW / (graphW + 120), canvasH / (graphH + 120))))
    panX = (canvasW - graphW * zoom) / 2 - minX * zoom
    panY = (canvasH - graphH * zoom) / 2 - minY * zoom
  }

  // ������ Node drag ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

  function onNodeDragMove(e: CustomEvent<{ id: string; dx: number; dy: number }>) {
    const { id, dx, dy } = e.detail
    const node = allNodes.find(n => n.id === id)
    if (!node) return
    const cur = nodePos(node)
    posOverrides.set(id, { x: cur.x + dx / zoom, y: cur.y + dy / zoom })
    posOverrides = posOverrides   // trigger reactivity
    dispatch('nodeDrag', { id, x: cur.x + dx / zoom, y: cur.y + dy / zoom })
  }

  function onNodeSelect(e: CustomEvent<string>) {
    dispatch('nodeSelect', e.detail)
  }

  // ������ Port drag (edge creation) ���������������������������������������������������������������������������������������������������������������������������������������

  interface PortDragState {
    nodeId:  string
    portId:  string
    kind:    'in' | 'out'
    startX:  number
    startY:  number
  }
  let portDrag: PortDragState | null = null
  let ghostX2 = 0
  let ghostY2 = 0

  function onPortDown(e: CustomEvent<{ nodeId: string; portId: string; x: number; y: number; kind: 'in' | 'out' }>) {
    const rect = container.getBoundingClientRect()
    portDrag = {
      nodeId:  e.detail.nodeId,
      portId:  e.detail.portId,
      kind:    e.detail.kind,
      startX: (e.detail.x - rect.left - panX) / zoom,
      startY: (e.detail.y - rect.top  - panY) / zoom,
    }
    ghostX2 = portDrag.startX
    ghostY2 = portDrag.startY
  }

  function onPortUp(e: CustomEvent<{ nodeId: string; portId: string }>) {
    if (!portDrag || portDrag.nodeId === e.detail.nodeId) { portDrag = null; return }
    const from = portDrag.kind === 'out' ? portDrag : { nodeId: e.detail.nodeId, portId: e.detail.portId }
    const to   = portDrag.kind === 'out' ? e.detail  : portDrag
    dispatch('edgeCreated', { fromNodeId: from.nodeId, fromPort: from.portId, toNodeId: to.nodeId, toPort: to.portId })
    portDrag = null
  }

  // ������ Edge port positions ������������������������������������������������������������������������������������������������������������������������������������������������������������

  /**
   * Compute the canvas-space (x,y) of a port.
   * Ports are on the left (in) or right (out) edge of the card.
   * Vertical position depends on port index within the port list.
   */
  function portPos(node: IrBpNode, portId: string, side: 'in'|'out'): { x: number; y: number } {
    const pos = nodePos(node)
    const ports = side === 'in' ? node.inPorts : node.outPorts
    const idx = ports.findIndex(p => p.id === portId)
    const portY = pos.y + HEADER_H + (idx + 0.5) * PORT_ROW_H + 4
    const portX = side === 'in' ? pos.x : pos.x + node.width
    return { x: portX, y: portY }
  }

  // ������ Derived: all nodes / edges across all contracts ���������������������������������������������������������������������

  $: allNodes = graph.contracts.flatMap(c => c.nodes)
  $: allEdges = graph.contracts.flatMap(c => c.edges)

  // Total canvas size (for SVG)
  const CANVAS_SIZE = 8000

  // ������ Grid dots ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

  const GRID_SIZE = 28
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div
  bind:this={container}
  class="relative w-full h-full overflow-hidden bg-ink-2"
  style="cursor: {panning ? 'grabbing' : 'grab'}"
  on:wheel={onWheel}
  on:mousemove={onMouseMove}
  on:mouseup={onMouseUp}
  on:mousedown={onBackgroundMouseDown}
>

  <!-- Transform group -->
  <div
    class="absolute"
    style="transform: translate({panX}px, {panY}px) scale({zoom}); transform-origin: 0 0;
           width: {CANVAS_SIZE}px; height: {CANVAS_SIZE}px;"
  >

    <!-- Grid dots background -->
    <svg class="absolute inset-0 pointer-events-none" width={CANVAS_SIZE} height={CANVAS_SIZE}>
      <defs>
        <pattern id="grid-dots" x="0" y="0" width={GRID_SIZE} height={GRID_SIZE} patternUnits="userSpaceOnUse">
          <circle cx={GRID_SIZE/2} cy={GRID_SIZE/2} r="1" fill="#2c1e15" />
        </pattern>
      </defs>
      <rect width={CANVAS_SIZE} height={CANVAS_SIZE} fill="url(#grid-dots)" />
    </svg>

    <!-- Contract label banners -->
    {#each graph.contracts as contract}
      {@const firstNode = contract.nodes[0]}
      {#if firstNode}
        {@const pos = nodePos(firstNode)}
        <div
          class="absolute text-[9px] font-bold uppercase tracking-wider text-warm/30 font-mono
                 pointer-events-none select-none"
          style="left: {pos.x}px; top: {pos.y - 26}px;"
        >
          {contract.kind === 'observed_contract' ? 'observed ' : ''}{contract.name}
        </div>
      {/if}
    {/each}

    <!-- SVG layer for edges (below nodes) -->
    <svg
      class="absolute inset-0 pointer-events-none overflow-visible"
      width={CANVAS_SIZE} height={CANVAS_SIZE}
    >
      {#each allEdges as edge (edge.id)}
        {@const fromNode = allNodes.find(n => n.id === edge.fromNodeId)}
        {@const toNode   = allNodes.find(n => n.id === edge.toNodeId)}
        {#if fromNode && toNode}
          {@const p1 = portPos(fromNode, edge.fromPort, 'out')}
          {@const p2 = portPos(toNode,   edge.toPort,   'in')}
          <BpEdgeLine
            x1={p1.x} y1={p1.y}
            x2={p2.x} y2={p2.y}
            selected={selectedNodeId === fromNode.id || selectedNodeId === toNode.id}
            dimmed={selectedNodeId !== null &&
                    selectedNodeId !== fromNode.id &&
                    selectedNodeId !== toNode.id}
          />
        {/if}
      {/each}

      <!-- Ghost edge during port drag -->
      {#if portDrag}
        {@const dragNode = allNodes.find(n => n.id === portDrag!.nodeId)}
        {#if dragNode}
          {@const startPos = portPos(dragNode, portDrag.portId, portDrag.kind)}
          <BpEdgeLine
            x1={portDrag.kind === 'out' ? startPos.x : ghostX2}
            y1={portDrag.kind === 'out' ? startPos.y : ghostY2}
            x2={portDrag.kind === 'out' ? ghostX2     : startPos.x}
            y2={portDrag.kind === 'out' ? ghostY2     : startPos.y}
            selected={true}
          />
        {/if}
      {/if}
    </svg>

    <!-- Node cards (HTML, absolute positioned) -->
    {#each allNodes as node (node.id)}
      {@const pos = nodePos(node)}
      <div style="position:absolute; left:{pos.x}px; top:{pos.y}px; width:{node.width}px; height:{node.height}px;">
        <BpNodeCard
          {node}
          selected={selectedNodeId === node.id}
          dimmed={selectedNodeId !== null && selectedNodeId !== node.id}
          inputValue={inputValues[node.name] || ''}
          evaluatedValue={evaluatedValues[node.name] || ''}
          error={nodeErrors[node.name] || ''}
          on:select={onNodeSelect}
          on:dragmove={onNodeDragMove}
          on:portdown={onPortDown}
          on:portup={onPortUp}
          on:gotosource={(e) => dispatch('gotoSource', e.detail)}
          on:inputValueChange={(e) => dispatch('inputValueChange', e.detail)}
        />
      </div>
    {/each}

  </div>

  <!-- HUD: zoom level + controls -->
  <div class="absolute bottom-3 right-3 flex items-center gap-2 pointer-events-none select-none">
    <div class="bg-ink-3/80 border border-ink-line rounded px-2 py-1 text-[10px] text-warm/40 font-mono">
      {Math.round(zoom * 100)}%
    </div>
  </div>

  <!-- Empty state -->
  {#if allNodes.length === 0}
    <div class="absolute inset-0 flex items-center justify-center pointer-events-none">
      <div class="text-center text-warm/30 space-y-1 font-mono">
        <div class="text-2xl text-warm/20">���</div>
        <div class="text-sm font-medium text-warm-3">No contract found</div>
        <div class="text-[10px] text-warm/30">Open a .ig file with a contract or pipeline</div>
      </div>
    </div>
  {/if}

</div>
