<!--
  BlueprintView.svelte ��� Top-level orchestrator for the Blueprint tab.

  Sync model:
    Editor ��� Blueprint:  content prop changes ��� parse + layout ��� graph
    Blueprint ��� Editor:  (Phase 2) graph mutation ��� codegen ��� emit codeChanged

  Phase 1: Read-only visualisation that live-syncs with editor content.
  Phase 2: Add node, delete node, add edge ��� will update editor.
-->
<script lang="ts">
  import { createEventDispatcher, tick } from 'svelte'
  import { parseIgSource } from '$lib/blueprint/parser'
  import { applyLayout }   from '$lib/blueprint/layout'
  import type { BpGraph }  from '$lib/blueprint/ir'
  import BlueprintCanvas   from './BlueprintCanvas.svelte'
  import { api } from '$lib/api'

  // Props from parent (IDE page)
  export let content:  string = ''    // current editor content (reactive)
  export let filePath: string = ''

  const dispatch = createEventDispatcher<{
    codeChanged: string   // (Phase 2) updated .ig source
    gotoSource:  number   // jump editor to line
    runContract: string   // contract name to execute
  }>()

  // ������ Demo content (shown when no file is open) ������������������������������������������������������������������������������������

  const DEMO_CONTENT = `module SparkCRM.Availability

observed contract AvailabilityProjection {
  input technician_id: String
  input date: String

  escape stream_collection

  read geo_signals: Collection[GeoSignal]
    from "geo_signal/{technician_id}/{date}"
    lifecycle :window

  read schedule: ScheduleFact
    from "schedule/{technician_id}/{date}"
    lifecycle :durable

  compute available_slots = compute_slots(geo_signals, schedule)

  snapshot snap = build_snapshot(available_slots, technician_id, date)
    lifecycle :durable

  output available_slots: Collection[TimeSlot]  lifecycle :window
  output snap: AvailabilitySnapshot             lifecycle :durable
}`

  let demoMode = false

  // ������ Reactive execution states ���������������������������������������������������������������������������������������������������������������������������������������
  let inputsMap: Record<string, Record<string, string>> = {}
  let evaluatedMap: Record<string, Record<string, string>> = {}
  let errorsMap: Record<string, Record<string, string>> = {}
  let liveRun = true

  // ������ Parse + layout ������������������������������������������������������������������������������������������������������������������������������������������������������������������������

  let graph: BpGraph | null = null
  let parseError = ''
  let selectedNodeId: string | null = null

  // Re-parse whenever content changes (or demo mode toggled)
  $: {
    const src = demoMode ? DEMO_CONTENT : content
    if (src !== undefined) rebuildGraph(src, filePath)
  }

  function rebuildGraph(src: string, fp: string) {
    try {
      const raw = parseIgSource(src, fp)
      graph = applyLayout(raw)
      parseError = ''
      selectedNodeId = null

      if (graph) {
        for (const contract of graph.contracts) {
          if (!inputsMap[contract.name]) {
            inputsMap[contract.name] = {}
          }
          if (!evaluatedMap[contract.name]) {
            evaluatedMap[contract.name] = {}
          }
          if (!errorsMap[contract.name]) {
            errorsMap[contract.name] = {}
          }
          for (const node of contract.nodes) {
            if (node.kind === 'input') {
              if (inputsMap[contract.name][node.name] === undefined) {
                inputsMap[contract.name][node.name] = ''
              }
            }
          }
        }
      }
    } catch (e) {
      parseError = String(e)
    }
  }

  // ������ Toolbar state ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������

  let canvasRef: BlueprintCanvas
  let showMinimap = false

  // Contract selector (for multi-contract files)
  $: contractNames = graph?.contracts.map(c => c.name) ?? []
  let focusedContract: string | null = null

  $: activeContractName = focusedContract || contractNames[0] || ''

  // Automatically trigger run when active contract or live state changes (debounced)
  $: if (liveRun && activeContractName && (content || demoMode)) {
    debounceExecute(activeContractName)
  }

  let debounceTimer: any = null
  function debounceExecute(contractName: string) {
    if (debounceTimer) clearTimeout(debounceTimer)
    debounceTimer = setTimeout(() => {
      executeVM(contractName)
    }, 200)
  }

  async function executeVM(contractName: string) {
    if (!contractName) return

    if (!inputsMap[contractName]) inputsMap[contractName] = {}
    if (!evaluatedMap[contractName]) evaluatedMap[contractName] = {}
    if (!errorsMap[contractName]) errorsMap[contractName] = {}

    const inputs = inputsMap[contractName]

    // Coerce input strings to appropriate types
    const parsedInputs: Record<string, any> = {}
    for (const [k, v] of Object.entries(inputs)) {
      if (v === '') continue
      const n = Number(v)
      if (!isNaN(n) && v.trim() !== '') { parsedInputs[k] = n; continue }
      if (v === 'true')  { parsedInputs[k] = true;  continue }
      if (v === 'false') { parsedInputs[k] = false; continue }
      try { parsedInputs[k] = JSON.parse(v) } catch { parsedInputs[k] = v }
    }

    try {
      // Build source from demo or editor content
      const src = demoMode ? DEMO_CONTENT : content
      if (src) {
        await api.loadContract(src, contractName)
      }

      const traced = await api.dispatchTraced(contractName, parsedInputs)

      const nextEvaluated: Record<string, string> = {}

      // 1. Process trace steps if they have values
      if (traced.trace && traced.trace.length > 0) {
        for (const step of traced.trace) {
          if (step.value_preview && step.value_preview !== '\u{27f3}' && step.value_preview !== '\u{2014}') {
            nextEvaluated[step.node] = step.value_preview
          }
        }
      }

      // 2. Map final result if present
      const result = traced.result
      if (result !== undefined && result !== null) {
        if (typeof result === 'object' && !Array.isArray(result)) {
          for (const [key, val] of Object.entries(result)) {
            nextEvaluated[key] = typeof val === 'string' ? val : JSON.stringify(val)
          }
        } else {
          const contract = graph?.contracts.find(c => c.name === contractName)
          if (contract) {
            const outputNodes = contract.nodes.filter(n => n.kind === 'output')
            if (outputNodes.length === 1) {
              const outName = outputNodes[0].name
              nextEvaluated[outName] = typeof result === 'string' ? result : JSON.stringify(result)
            }
          }
        }
      }

      evaluatedMap[contractName] = nextEvaluated
      errorsMap[contractName] = {} // clear errors

      // Trigger Svelte update
      evaluatedMap = evaluatedMap
      errorsMap = errorsMap
    } catch (e) {
      const errStr = String(e)
      const nextErrors: Record<string, string> = {}
      let matchedNode = false

      const contract = graph?.contracts.find(c => c.name === contractName)
      if (contract) {
        for (const node of contract.nodes) {
          const escapedName = node.name.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&')
          const regex = new RegExp(`\\b${escapedName}\\b`, 'i')
          if (regex.test(errStr)) {
            nextErrors[node.name] = errStr
            matchedNode = true
          }
        }

        if (!matchedNode) {
          const outputNodes = contract.nodes.filter(n => n.kind === 'output')
          if (outputNodes.length > 0) {
            for (const outNode of outputNodes) {
              nextErrors[outNode.name] = errStr
            }
          } else {
            nextErrors[contractName] = errStr
          }
        }
      }

      errorsMap[contractName] = nextErrors
      evaluatedMap[contractName] = {} // clear evaluated values on error

      // Trigger Svelte update
      errorsMap = errorsMap
      evaluatedMap = evaluatedMap
    }
  }

  function handleInputValueChange(e: CustomEvent<{ name: string; value: string }>) {
    const { name, value } = e.detail
    const contractName = activeContractName
    if (!contractName) return

    if (!inputsMap[contractName]) {
      inputsMap[contractName] = {}
    }
    inputsMap[contractName][name] = value
    inputsMap = inputsMap // trigger update

    if (liveRun) {
      debounceExecute(contractName)
    }
  }

  // ������ Node selection ������������������������������������������������������������������������������������������������������������������������������������������������������������������������

  function onNodeSelect(e: CustomEvent<string>) {
    selectedNodeId = selectedNodeId === e.detail ? null : e.detail
  }

  // ������ Selected node detail ������������������������������������������������������������������������������������������������������������������������������������������������������

  $: selectedNode = graph?.contracts.flatMap(c => c.nodes).find(n => n.id === selectedNodeId)

  // ������ Stats ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

  $: nodeCount = graph?.contracts.reduce((n, c) => n + c.nodes.length, 0) ?? 0
  $: edgeCount = graph?.contracts.reduce((n, c) => n + c.edges.length, 0) ?? 0
</script>

<div class="flex flex-col h-full overflow-hidden bg-ink-2">

  <!-- ������ Toolbar ��������������������������������������������������������������������������������������������������������������������������������������������������������������������������������� -->
  <div class="flex items-center gap-2 px-3 py-1.5 bg-ink-1 border-b border-ink-line
              flex-shrink-0 text-xs font-mono">

    <span class="text-ignite font-bold tracking-wider text-[10px] uppercase">Blueprint</span>
    <span class="text-warm/20">|</span>

    <!-- Contract breadcrumb -->
    {#if graph && graph.moduleDecl}
      <span class="text-warm/40 font-mono">{graph.moduleDecl}</span>
      <span class="text-warm/20">���</span>
    {/if}
    {#each contractNames as name}
      <button
        on:click={() => focusedContract = focusedContract === name ? null : name}
        class="px-1.5 py-0.5 rounded text-[10px] transition-colors cursor-pointer border
               {focusedContract === name
                 ? 'bg-ignite/15 text-ignite border-ignite/20 font-semibold'
                 : 'text-warm/50 border-transparent hover:text-warm-3 hover:bg-ink-2'}"
      >{name}</button>
    {/each}

    <div class="flex-1"></div>

    <!-- Stats -->
    {#if graph}
      <span class="text-warm/40">{nodeCount} nodes</span>
      <span class="text-warm/20">��</span>
      <span class="text-warm/40">{edgeCount} edges</span>
      <span class="text-warm/20">|</span>
    {/if}

    <!-- Demo mode -->
    {#if !content}
      <button
        on:click={() => { demoMode = !demoMode; setTimeout(() => canvasRef?.fitView(), 80) }}
        class="px-2 py-0.5 rounded text-[10px] transition-colors cursor-pointer border
               {demoMode ? 'bg-ember/15 text-ember border-ember/20 font-semibold' : 'text-warm/50 border-transparent hover:text-warm-3 hover:bg-ink-2'}"
        title="Load demo AvailabilityProjection contract"
      >{demoMode ? '��� Demo' : '��� Try Demo'}</button>
    {/if}

    <!-- Fit view -->
    <button
      on:click={() => canvasRef?.fitView()}
      class="px-2 py-0.5 rounded text-warm/50 hover:text-warm-3 hover:bg-ink-2 border border-transparent
             transition-colors text-[10px] cursor-pointer"
      title="Fit all nodes in view"
    >��� Fit</button>

    <!-- Reset zoom -->
    <button
      on:click={() => canvasRef?.resetView()}
      class="px-2 py-0.5 rounded text-warm/50 hover:text-warm-3 hover:bg-ink-2 border border-transparent
             transition-colors text-[10px] cursor-pointer"
      title="Reset zoom to 100%"
    >1:1</button>

    <!-- Live execution toggle -->
    {#if contractNames.length > 0}
      {@const contractToRun = focusedContract || contractNames[0]}
      <button
        on:click={() => {
          liveRun = !liveRun
          if (liveRun) {
            executeVM(contractToRun)
          }
        }}
        class="px-2 py-0.5 rounded text-[10px] transition-all cursor-pointer border font-semibold
               {liveRun
                 ? 'bg-core/15 text-core border-core/30 font-bold'
                 : 'text-warm/40 border-ink-line/50 hover:text-warm-3 hover:bg-ink-2'}"
        title="Toggle real-time reactive execution on input changes"
      >
        <span>��� Live</span>
      </button>
    {/if}

    <!-- Run button -->
    {#if contractNames.length > 0}
      {@const contractToRun = focusedContract || contractNames[0]}
      <button
        on:click={() => {
          executeVM(contractToRun)
          dispatch('runContract', contractToRun)
        }}
        class="px-2 py-0.5 bg-core text-ink-1 hover:bg-core/85 border border-core/20 rounded font-semibold
               transition-colors text-[10px] flex items-center gap-1 shrink-0 ml-1 cursor-pointer"
        title="Run contract (������)"
      >
        <span>��� Run</span>
      </button>
    {/if}
  </div>

  <!-- ������ Main split: canvas + inspector ������������������������������������������������������������������������������������������������������������������ -->
  <div class="flex flex-1 min-h-0 overflow-hidden">

    <!-- Canvas -->
    <div class="flex-1 relative min-w-0">
      {#if parseError}
        <div class="absolute inset-0 flex items-center justify-center">
          <div class="bg-red-950/60 border border-red-800 rounded-lg p-4 max-w-md text-xs text-red-300">
            <div class="font-bold mb-1">Parse error</div>
            <pre class="text-[10px] text-red-400 whitespace-pre-wrap">{parseError}</pre>
          </div>
        </div>
      {:else if graph}
        <BlueprintCanvas
          bind:this={canvasRef}
          {graph}
          {selectedNodeId}
          inputValues={inputsMap[activeContractName] || {}}
          evaluatedValues={evaluatedMap[activeContractName] || {}}
          nodeErrors={errorsMap[activeContractName] || {}}
          on:nodeSelect={onNodeSelect}
          on:gotoSource={(e) => dispatch('gotoSource', e.detail)}
          on:inputValueChange={handleInputValueChange}
        />
      {:else}
        <div class="absolute inset-0 flex items-center justify-center text-gray-700 text-xs">
          Parsing���
        </div>
      {/if}
    </div>

    <!-- Inspector sidebar (only when node selected) -->
    {#if selectedNode}
      <div class="w-52 border-l border-ink-line bg-ink-1 flex flex-col overflow-hidden flex-shrink-0 text-xs font-mono">
        <div class="px-3 py-2 border-b border-ink-line flex items-center justify-between flex-shrink-0 bg-ink-1">
          <span class="font-bold text-warm-3 truncate">{selectedNode.name}</span>
          <button
            on:click={() => selectedNodeId = null}
            class="text-warm/40 hover:text-warm-3 text-xs ml-1 flex-shrink-0 cursor-pointer"
          >���</button>
        </div>

        <div class="flex-1 overflow-y-auto p-3 space-y-3 bg-ink-2/30">
          <!-- Kind badge -->
          <div class="flex items-center gap-2">
            <span class="text-[9px] uppercase tracking-widest text-warm/40 font-bold">Kind</span>
            <span class="text-warm-3 font-mono">{selectedNode.kind}</span>
          </div>

          <!-- Source line -->
          <div>
            <div class="text-[9px] uppercase tracking-widest text-warm/40 font-bold mb-1">Source</div>
            <button
              on:click={() => dispatch('gotoSource', selectedNode!.sourceLine)}
              class="text-ignite hover:text-ember transition-colors font-mono cursor-pointer"
            >Line {selectedNode.sourceLine}</button>
          </div>

          <!-- All properties -->
          {#if Object.keys(selectedNode.props).length > 0}
            <div>
              <div class="text-[9px] uppercase tracking-widest text-warm/40 font-bold mb-1">Props</div>
              <div class="space-y-1">
                {#each Object.entries(selectedNode.props) as [k, v]}
                  <div class="space-y-0.5">
                    <div class="text-warm/40">{k}</div>
                    <div class="text-warm-3 font-mono break-all bg-ink-3 border border-ink-line/50 rounded px-1.5 py-0.5">{v}</div>
                  </div>
                {/each}
              </div>
            </div>
          {/if}

          <!-- Ports -->
          {#if selectedNode.inPorts.length > 0}
            <div>
              <div class="text-[9px] uppercase tracking-widest text-warm/40 font-bold mb-1">Inputs</div>
              {#each selectedNode.inPorts as port}
                <div class="flex items-center gap-1.5 py-0.5">
                  <div class="w-2 h-2 rounded-full border border-ink-line bg-ink-3 flex-shrink-0"></div>
                  <span class="text-warm-3 font-mono">{port.label}</span>
                  {#if port.type}<span class="text-warm/40">: {port.type}</span>{/if}
                </div>
              {/each}
            </div>
          {/if}

          {#if selectedNode.outPorts.length > 0}
            <div>
              <div class="text-[9px] uppercase tracking-widest text-warm/40 font-bold mb-1">Outputs</div>
              {#each selectedNode.outPorts as port}
                <div class="flex items-center gap-1.5 py-0.5">
                  <span class="text-warm-3 font-mono">{port.label}</span>
                  {#if port.type}<span class="text-warm/40">: {port.type}</span>{/if}
                  <div class="w-2 h-2 rounded-full border border-ink-line bg-ink-3 flex-shrink-0 ml-auto"></div>
                </div>
              {/each}
            </div>
          {/if}
        </div>
      </div>
    {/if}

  </div>

  <!-- ������ Status bar ������������������������������������������������������������������������������������������������������������������������������������������������������������������������ -->
  <div class="flex items-center gap-3 px-3 py-1 bg-ink-1 border-t border-ink-line
              flex-shrink-0 text-[10px] text-warm/40 select-none font-mono">
    <span>Phase 1 ��� read-only visualisation</span>
    <span>��</span>
    <span>scroll to zoom �� drag to pan �� click node to inspect</span>
    {#if selectedNode}
      <span class="text-ignite ml-auto font-semibold">{selectedNode.name} selected</span>
    {/if}
  </div>

</div>
