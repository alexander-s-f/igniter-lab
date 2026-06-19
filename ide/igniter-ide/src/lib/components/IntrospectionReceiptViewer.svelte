<script lang="ts">
  import { onMount } from 'svelte'
  import { api } from '$lib/api'
  import type { WorkspaceConfig, IntrospectionReceipt, IntrospectionNode } from '$lib/types'
  import IntrospectionTreeInspectorNode from './IntrospectionTreeInspectorNode.svelte'

  // Svelte 5 props
  let { workspace }: { workspace: WorkspaceConfig | null } = $props()

  // State variables
  let receiptPath = $state('')
  let receipt = $state<IntrospectionReceipt | null>(null)
  let loading = $state(false)
  let errorMsg = $state<string | null>(null)
  let selectedNodeId = $state<string | null>(null)

  let lastReceiptSignature = ''
  let reloadInterval: any = null

  // Initialize path when workspace updates
  $effect(() => {
    if (workspace && !receiptPath) {
      receiptPath = `${workspace.root_dir}/igniter-gui-engine/out/scene_introspection_receipt.json`
      loadReceipt()
    }
  })

  onMount(() => {
    reloadInterval = setInterval(() => {
      if (workspace && receiptPath && !loading) {
        reloadReceiptSilently()
      }
    }, 1500)

    return () => {
      clearInterval(reloadInterval)
    }
  })

  async function reloadReceiptSilently() {
    try {
      if (!workspace) return
      // Parse and validate via the bounded backend command; do not bypass the
      // introspection workspace/path boundary with a generic file read.
      const newReceipt = await api.readIntrospectionReceipt(receiptPath, workspace.root_dir)
      const newSignature = JSON.stringify(newReceipt)
      if (newSignature === lastReceiptSignature) return

      lastReceiptSignature = newSignature
      errorMsg = null
      receipt = newReceipt

      if (!selectedNodeId && newReceipt.nodes) {
        selectedNodeId = Object.keys(newReceipt.nodes)[0] || null
      }
    } catch (err: any) {
      // Don't crash during background reload, but show error if invalid JSON
      errorMsg = `Malformed Receipt: Failed to reload.\n\nError: ${err?.message || err}`
      receipt = null
      selectedNodeId = null
    }
  }

  async function loadReceipt() {
    if (!receiptPath) {
      errorMsg = 'Please specify a path to scene_introspection_receipt.json'
      return
    }
    if (!workspace) return

    loading = true
    errorMsg = null
    receipt = null
    selectedNodeId = null

    try {
      // 1. Read/validate via Tauri command boundary
      const parsed = await api.readIntrospectionReceipt(receiptPath, workspace.root_dir)
      receipt = parsed

      lastReceiptSignature = JSON.stringify(parsed)

      if (parsed.nodes) {
        // Select root if exists, else first key
        if (parsed.nodes['root']) {
          selectedNodeId = 'root'
        } else {
          selectedNodeId = Object.keys(parsed.nodes)[0] || null
        }
      }
    } catch (err: any) {
      errorMsg = `Missing or Invalid Introspection Receipt:\n${receiptPath}\n\nError: ${err?.message || err}`
    } finally {
      loading = false
    }
  }

  // Tree representation computed reactively (Svelte 5 derived state)
  interface TreeNode {
    node: IntrospectionNode
    children: TreeNode[]
  }

  let treeRoot = $derived.by<TreeNode | null>(() => {
    if (!receipt || !receipt.nodes) return null

    const nodeMap: Record<string, TreeNode> = {}
    for (const [id, node] of Object.entries(receipt.nodes)) {
      nodeMap[id] = { node, children: [] }
    }

    let rootNode: TreeNode | null = null

    for (const [id, treeNode] of Object.entries(nodeMap)) {
      const parentId = treeNode.node.parent
      if (parentId && parentId !== 'root' && nodeMap[parentId]) {
        nodeMap[parentId].children.push(treeNode)
      } else {
        if (!parentId) {
          rootNode = treeNode
        } else if (parentId === 'root' && id !== 'root') {
          nodeMap[parentId].children.push(treeNode)
        } else {
          if (!rootNode) rootNode = treeNode
        }
      }
    }

    return rootNode
  })

  // Selected node derived
  let selectedNode = $derived(
    receipt && selectedNodeId ? receipt.nodes[selectedNodeId] || null : null
  )

  // Layout Viewport bounds
  let canvasRoot = $derived(
    receipt ? Object.values(receipt.nodes).find(n => n.id === 'root' || !n.parent) : null
  )
  let canvasW = $derived(canvasRoot?.computed_bounds?.w || 1024)
  let canvasH = $derived(canvasRoot?.computed_bounds?.h || 768)

  function handleSelectNode(id: string) {
    selectedNodeId = id
  }
</script>

<div class="flex flex-col w-full h-full min-h-0 bg-ink text-warm-3 font-mono">
  
  <!-- Path Inputs -->
  <div class="flex items-center gap-2 px-3 py-2 border-b border-ink-line bg-ink-1 shrink-0">
    <span class="text-xs text-warm select-none">Receipt Path:</span>
    <input
      type="text"
      bind:value={receiptPath}
      placeholder="igniter-gui-engine/out/scene_introspection_receipt.json"
      class="flex-1 bg-ink border border-ink-line rounded px-2 py-1 text-xs text-grey-3 font-mono h-7 min-w-0"
    />
    <button
      onclick={loadReceipt}
      disabled={loading}
      class="h-7 px-3 bg-ignite/15 hover:bg-ignite/25 border border-ignite/30 text-ignite rounded text-xs font-semibold cursor-pointer shrink-0 transition-colors flex items-center gap-1.5"
    >
      {#if loading}
        <span class="animate-pulse">⏳ Loading...</span>
      {:else}
        <span>🔄 Refresh</span>
      {/if}
    </button>
  </div>

  <!-- Workspace Missing Warning -->
  {#if !workspace}
    <div class="flex-1 flex flex-col items-center justify-center p-8 text-center bg-ink-1">
      <span class="text-4xl mb-3">⚠️</span>
      <h3 class="text-warm-3 font-bold mb-1">No Active Workspace</h3>
      <p class="text-xs text-warm max-w-sm">Please open a workspace directory first to load GUI introspection receipts.</p>
    </div>

  <!-- Error / Missing Receipt State -->
  {:else if errorMsg}
    <div class="flex-1 flex flex-col items-center justify-center p-8 bg-ink-1 overflow-auto">
      <div class="max-w-xl w-full border border-oof/40 bg-oof/5 p-6 rounded-lg shadow-lg relative">
        <h3 class="text-oof font-bold flex items-center gap-2 mb-3">
          <span>❌</span>
          <span>Receipt Load Error</span>
        </h3>
        <pre class="text-xs text-warm-3 bg-ink p-4 rounded border border-ink-line whitespace-pre-wrap font-mono leading-relaxed max-h-96 overflow-y-auto">{errorMsg}</pre>
        <button
          onclick={loadReceipt}
          class="mt-4 bg-oof text-ink-1 font-bold font-mono text-xs px-3 py-1.5 rounded cursor-pointer hover:opacity-90 transition-opacity"
        >
          Try Again
        </button>
      </div>
    </div>

  <!-- Main View -->
  {:else if receipt}
    <div class="flex-1 flex min-h-0 overflow-hidden divide-x divide-ink-line">

      <!-- Left Column: Interactive Box-Model Visualizer -->
      <div class="w-1/2 flex flex-col min-h-0 bg-ink-1 overflow-hidden">
        <div class="px-3 py-1.5 border-b border-ink-line bg-ink-2 shrink-0 flex justify-between items-center select-none font-sans">
          <span class="text-xs font-bold text-warm uppercase tracking-wider">Box-Model Diagram</span>
          <span class="text-[9px] text-warm/40 font-mono bg-ink-1 border border-ink-line px-1.5 rounded">Bounded Bounds View</span>
        </div>
        <div class="flex-1 p-6 overflow-auto flex items-center justify-center">
          <div 
            class="relative border border-ink-line bg-ink rounded shadow-2xl overflow-hidden transition-all duration-300"
            style="width: 100%; aspect-ratio: {canvasW} / {canvasH}; max-width: {canvasW}px; max-height: 80vh;"
          >
            {#each Object.values(receipt.nodes) as node}
              {#if node.computed_bounds}
                <!-- svelte-ignore a11y_click_events_have_key_events -->
                <!-- svelte-ignore a11y_no_static_element_interactions -->
                <div
                  onclick={(e) => { e.stopPropagation(); handleSelectNode(node.id) }}
                  class="absolute transition-all duration-150 border cursor-pointer group/box
                    {selectedNodeId === node.id 
                      ? 'border-2 border-ignite bg-ignite/15 shadow-xl z-30' 
                      : node.slot_bound 
                        ? 'border-dashed border-temporal/60 bg-temporal/5 hover:bg-temporal/10 hover:border-temporal hover:z-20' 
                        : node.status === 'skip'
                          ? 'border-line/20 bg-ink-3/10 opacity-30'
                          : 'border-line/50 bg-ink-2/10 hover:border-warm hover:bg-warm/5 hover:z-10'
                    }"
                  style="
                    left: { (node.computed_bounds.x / canvasW) * 100 }%;
                    top: { (node.computed_bounds.y / canvasH) * 100 }%;
                    width: { (node.computed_bounds.w / canvasW) * 100 }%;
                    height: { (node.computed_bounds.h / canvasH) * 100 }%;
                    z-index: { selectedNodeId === node.id ? 100 : node.z_index };
                  "
                  title="{node.id} ({node.type})"
                >
                  <!-- Label on hover / selection -->
                  <div class="absolute -top-4 left-0 text-[8px] font-mono select-none px-1 rounded shadow-sm opacity-0 group-hover/box:opacity-100 transition-opacity pointer-events-none z-40
                    {selectedNodeId === node.id 
                      ? 'bg-ignite text-ink-1 opacity-100' 
                      : 'bg-ink-1 text-grey-3'}"
                  >
                    {node.id}
                  </div>
                </div>
              {/if}
            {/each}
          </div>
        </div>
      </div>

      <!-- Right Column: Tree & Detail Inspector -->
      <div class="w-1/2 flex flex-col min-h-0 divide-y divide-ink-line">

        <div class="h-3/5 flex min-h-0 divide-x divide-ink-line">
          
          <!-- Recursive Tree Walk -->
          <div class="w-1/2 flex flex-col min-h-0">
            <div class="px-3 py-1.5 border-b border-ink-line bg-ink-2 shrink-0 select-none">
              <span class="text-xs font-bold text-warm uppercase tracking-wider font-sans">Tree Inspector</span>
            </div>
            <div class="flex-1 p-2 overflow-y-auto bg-ink min-h-0">
              {#if treeRoot}
                <IntrospectionTreeInspectorNode treeNode={treeRoot} onSelectNode={handleSelectNode} {selectedNodeId} depth={0} />
              {:else}
                <div class="text-warm/40 italic text-center py-6 text-xs">No tree hierarchy available.</div>
              {/if}
            </div>
          </div>

          <!-- Properties Panel -->
          <div class="w-1/2 flex flex-col min-h-0 bg-ink-1">
            <div class="px-3 py-1.5 border-b border-ink-line bg-ink-2 shrink-0 select-none">
              <span class="text-xs font-bold text-warm uppercase tracking-wider font-sans">Node Properties</span>
            </div>
            <div class="flex-1 p-4 overflow-y-auto text-xs space-y-4">
              {#if selectedNode}
                <div>
                  <span class="text-grey font-mono block mb-1">Node ID:</span>
                  <span class="text-ignite font-bold font-mono text-sm bg-ink border border-ink-line px-2 py-0.5 rounded block">{selectedNode.id}</span>
                </div>

                <div>
                  <span class="text-grey font-mono block mb-1">Type:</span>
                  <span class="text-warm-3 bg-ink border border-ink-line px-2 py-0.5 rounded block font-mono">{selectedNode.type}</span>
                </div>

                <div>
                  <span class="text-grey font-mono block mb-1">Parent:</span>
                  <span class="text-grey-3 font-mono">
                    {#if selectedNode.parent}
                      <button onclick={() => handleSelectNode(selectedNode!.parent!)} class="text-ignite underline hover:text-ignite-hover cursor-pointer border-none bg-transparent p-0">
                        {selectedNode.parent}
                      </button>
                    {:else}
                      <span class="italic text-grey/40">none (root)</span>
                    {/if}
                  </span>
                </div>

                <div class="grid grid-cols-2 gap-3">
                  <div>
                    <span class="text-grey font-mono block mb-0.5">z-index:</span>
                    <span class="text-warm-3 font-bold font-mono">{selectedNode.z_index}</span>
                  </div>
                  <div>
                    <span class="text-grey font-mono block mb-0.5">Status:</span>
                    <span class="px-1.5 py-0.5 rounded text-[10px] font-bold uppercase
                      {selectedNode.status === 'active' ? 'bg-core/15 text-core border border-core/30' : 'bg-grey/15 text-grey border border-grey/30'}"
                    >
                      {selectedNode.status}
                    </span>
                  </div>
                </div>

                <div>
                  <span class="text-grey font-mono block mb-1">Containment Model:</span>
                  <div class="grid grid-cols-2 gap-2 text-[10px] font-mono">
                    <div class="bg-ink border border-ink-line p-1.5 rounded">
                      <span class="text-grey block">Containment:</span>
                      <span class="text-warm-3 font-bold">{selectedNode.containment}</span>
                    </div>
                    <div class="bg-ink border border-ink-line p-1.5 rounded">
                      <span class="text-grey block">Overflow:</span>
                      <span class="text-warm-3 font-bold">{selectedNode.overflow_allowance}</span>
                    </div>
                  </div>
                </div>

                <div>
                  <span class="text-grey font-mono block mb-1">Structural Overwrites:</span>
                  <span class="text-warm-3 font-mono font-bold">
                    {selectedNode.allow_structural_overwrites ? 'Allowed (Dangerous)' : 'Disallowed (Safe)'}
                  </span>
                </div>

                {#if selectedNode.computed_bounds}
                  <div>
                    <span class="text-grey font-mono block mb-1">Computed Bounds:</span>
                    <div class="grid grid-cols-4 gap-1 font-mono text-[10px] bg-ink border border-ink-line p-2 rounded">
                      <div><span class="text-grey">X:</span> {selectedNode.computed_bounds.x}</div>
                      <div><span class="text-grey">Y:</span> {selectedNode.computed_bounds.y}</div>
                      <div><span class="text-grey">W:</span> {selectedNode.computed_bounds.w}</div>
                      <div><span class="text-grey">H:</span> {selectedNode.computed_bounds.h}</div>
                    </div>
                  </div>
                {/if}

                {#if selectedNode.slot_bound}
                  <div class="border border-temporal/30 bg-temporal/5 p-2 rounded relative">
                    <span class="text-temporal font-bold block text-[10px] mb-1">⚡ SLOT BOUND STATE</span>
                    <div class="space-y-1">
                      {#if selectedNode.referenced_slots.length > 0}
                        <div>
                          <span class="text-[10px] text-grey">Referenced Slots:</span>
                          <div class="flex flex-wrap gap-1 mt-0.5">
                            {#each selectedNode.referenced_slots as slot}
                              <span class="bg-ink border border-temporal/30 text-temporal text-[9px] px-1 rounded">{slot}</span>
                            {/each}
                          </div>
                        </div>
                      {/if}
                      {#if selectedNode.scoped_slots.length > 0}
                        <div>
                          <span class="text-[10px] text-grey">Scoped Slots:</span>
                          <div class="flex flex-wrap gap-1 mt-0.5">
                            {#each selectedNode.scoped_slots as slot}
                              <span class="bg-ink border border-ignite/30 text-ignite text-[9px] px-1 rounded">{slot}</span>
                            {/each}
                          </div>
                        </div>
                      {/if}
                    </div>
                  </div>
                {/if}

              {:else}
                <div class="text-warm/40 italic text-center py-8">Select a node to inspect</div>
              {/if}
            </div>
          </div>

        </div>

        <!-- Bottom Panel: General Receipt Metadata & Non-claims -->
        <div class="h-2/5 flex flex-col min-h-0 bg-ink overflow-hidden p-3 font-mono text-xs">
          <div class="border-b border-ink-line pb-1.5 mb-2 select-none">
            <span class="text-xs font-bold text-warm uppercase tracking-wider font-sans">Receipt Metadata & Non-Claims</span>
          </div>
          <div class="flex-1 overflow-y-auto space-y-3">
            <div class="grid grid-cols-3 gap-2">
              <div class="bg-ink-1 border border-ink-line p-2 rounded">
                <span class="text-grey block mb-0.5">View ID:</span>
                <span class="text-warm-3 font-bold">{receipt.view_id}</span>
              </div>
              <div class="bg-ink-1 border border-ink-line p-2 rounded">
                <span class="text-grey block mb-0.5">Node Count:</span>
                <span class="text-warm-3 font-bold">{receipt.node_count} nodes</span>
              </div>
              <div class="bg-ink-1 border border-ink-line p-2 rounded truncate" title={receipt.scene_digest}>
                <span class="text-grey block mb-0.5">Scene Digest:</span>
                <span class="text-warm-3 text-[10px] truncate block">{receipt.scene_digest.replace('sha256:', '')}</span>
              </div>
            </div>

            <div>
              <span class="text-grey block mb-1">Receipt Non-Claims Bound:</span>
              <div class="flex flex-wrap gap-1.5">
                {#each receipt.non_claims as claim}
                  <span class="bg-oof/15 text-oof border border-oof/25 text-[9px] px-2 py-0.5 rounded font-bold uppercase tracking-wider">
                    {claim}
                  </span>
                {/each}
              </div>
            </div>
          </div>
        </div>

      </div>

    </div>
  {:else}
    <div class="flex-1 flex flex-col items-center justify-center p-8 text-center bg-ink-1">
      <span class="text-4xl mb-3">📂</span>
      <h3 class="text-warm-3 font-bold mb-1">No Receipt Loaded</h3>
      <p class="text-xs text-warm max-w-sm mb-4">Launch the introspection receipt viewer and load a valid scene receipt artifact.</p>
      <button
        onclick={loadReceipt}
        class="bg-ignite text-ink-1 font-bold font-mono text-xs px-4 py-2 rounded cursor-pointer hover:opacity-90 transition-opacity"
      >
        Load Receipt
      </button>
    </div>
  {/if}

</div>

<style>
  /* Premium Scrollbar styling */
  ::-webkit-scrollbar {
    width: 6px;
    height: 6px;
  }
  ::-webkit-scrollbar-track {
    background: var(--ink-1);
  }
  ::-webkit-scrollbar-thumb {
    background: var(--line);
    border-radius: 3px;
  }
  ::-webkit-scrollbar-thumb:hover {
    background: var(--line-2);
  }
</style>
