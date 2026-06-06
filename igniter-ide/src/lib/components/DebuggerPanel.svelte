<script lang="ts">
  import { createEventDispatcher, onMount } from 'svelte'
  import { api } from '$lib/api'
  import { debuggerStore, artifacts } from '$lib/stores/artifacts'
  import type { DebugEvent } from '$lib/stores/artifacts'

  const dispatch = createEventDispatcher<{ replay: any }>()

interface PassportCapability {
  sandbox_dir?: string
  read_allowed?: boolean
  write_allowed?: boolean
}

function passportCapabilities(summary: any): Array<[string, PassportCapability]> {
  const capabilities = summary?.required_capabilities
  if (!capabilities || typeof capabilities !== 'object') return []
  return Object.entries(capabilities as Record<string, PassportCapability>)
}

function boundParamFor(summary: any, capId: string): string {
  const bindings = summary?.capability_bindings
  if (!bindings || typeof bindings !== 'object') return 'none'
  return Object.entries(bindings as Record<string, string>).find(([, value]) => value === capId)?.[0] || 'none'
}

  let filterType: 'all' | 'compile' | 'run' = 'all'
  let selectedEventId: string = ''
  let selectedFile: string = ''
  let fileContent: string = ''
  let fileError: string = ''
  let isLoadingFile: boolean = false

  // Pinned Regression Case
  const PINNED_EVENT: DebugEvent = {
    id: 'pinned-loop-regression',
    type: 'run',
    timestamp: 1783324800000, // Pinned date
    contractName: 'Accumulate',
    success: false,
    durationMs: 6,
    inputs: { items: [1, 2, 3] },
    error: 'VM execution error: Missing loop collection expr',
    errorStage: 'VM compile'
  }

  // Combine pinned event with store events
  $: allEvents = [PINNED_EVENT, ...$debuggerStore]

  $: filteredEvents = allEvents.filter(e => {
    if (filterType === 'all') return true
    return e.type === filterType
  })

  $: selectedEvent = allEvents.find(e => e.id === selectedEventId) || allEvents[0]

  // Dynamic Loop Mismatch Diagnostics state
  let semanticLoopNode: any = null
  let compiledLoopNode: any = null
  let loopDiagError: string = ''
  let loopDiagLoading: boolean = false
  let showLoopAnalysis = false
  let loopResolutionStatus: 'resolved' | 'failed' | 'not_a_loop' = 'not_a_loop'

  // Pinned loop node data
  const PINNED_SEMANTIC_NODE = {
    kind: "loop",
    name: "Accumulate",
    expr: {
      kind: "ref",
      name: "items"
    },
    options: {
      max_steps: 1000
    },
    body_nodes: [
      {
        name: "total",
        expr: {
          kind: "binary_op",
          op: "+",
          left: { "kind": "ref", "name": "total" },
          right: { "kind": "ref", "name": "item" }
        }
      }
    ]
  }

  const PINNED_COMPILED_NODE = {
    node_id: "node_Accumulate",
    name: "Accumulate",
    kind: "loop",
    fragment_class: "core",
    type_tag: "Integer",
    lifecycle: "session",
    obs_kind: "value_observation",
    dependencies: ["input:items"],
    expression: {
      kind: "ref",
      name: "items"
    }
  }

  // Watch selected event to reset file inspect or trigger dynamic diagnostics
  $: if (selectedEvent) {
    selectedFile = ''
    fileContent = ''
    fileError = ''

    if (selectedEvent.id === 'pinned-loop-regression') {
      semanticLoopNode = PINNED_SEMANTIC_NODE
      compiledLoopNode = PINNED_COMPILED_NODE
      loopDiagError = ''
      showLoopAnalysis = true
      loopResolutionStatus = 'failed'
    } else {
      // Find compile artifact directory for this contract
      let artifactDir = selectedEvent.type === 'compile' ? selectedEvent.artifactDir : null
      if (!artifactDir) {
        const latestBuild = $debuggerStore.find(e =>
          e.type === 'compile' &&
          e.contractName === selectedEvent?.contractName &&
          e.artifactDir
        )
        artifactDir = latestBuild?.artifactDir || null
      }

      if (artifactDir) {
        loadDynamicLoopDiagnostics(selectedEvent.contractName, artifactDir)
      } else {
        semanticLoopNode = null
        compiledLoopNode = null
        loopDiagError = ''
        showLoopAnalysis = false
        loopResolutionStatus = 'not_a_loop'
      }
    }
  }

  async function loadDynamicLoopDiagnostics(contractName: string, artifactDir: string) {
    loopDiagLoading = true
    loopDiagError = ''
    semanticLoopNode = null
    compiledLoopNode = null
    showLoopAnalysis = false
    loopResolutionStatus = 'not_a_loop'
    try {
      // Read semantic_ir_program.json
      const semText = await api.readFile(`${artifactDir}/semantic_ir_program.json`)
      const semJson = JSON.parse(semText)
      const contractsArr = semJson.contracts || []
      let semNode: any = null
      for (const c of contractsArr) {
        const nodes = c.nodes || c.compute_nodes || []
        semNode = nodes.find((n: any) => n.kind === 'loop')
        if (semNode) break
      }

      if (!semNode) {
        showLoopAnalysis = false
        loopResolutionStatus = 'not_a_loop'
        return
      }

      semanticLoopNode = semNode
      showLoopAnalysis = true

      // Read compiled contract file (convert HelloWorld to hello_world)
      const snakeName = contractName.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase()
      const compText = await api.readFile(`${artifactDir}/contracts/${snakeName}.json`)
      const compJson = JSON.parse(compText)
      const compNodes = compJson.compute_nodes || compJson.nodes || []
      const compNode = compNodes.find((n: any) => n.kind === 'loop' || n.name === semNode?.name)
      compiledLoopNode = compNode

      if (compNode) {
        const hasExpr = compNode.expr !== undefined || compNode.expression !== undefined
        const hasBody = compNode.body_nodes !== undefined && compNode.body_nodes.length > 0
        if (hasExpr && hasBody) {
          loopResolutionStatus = 'resolved'
        } else {
          loopResolutionStatus = 'failed'
        }
      } else {
        loopResolutionStatus = 'failed'
      }
    } catch (e) {
      loopDiagError = `Failed to load loop nodes: ${String(e)}`
    } finally {
      loopDiagLoading = false
    }
  }

  // List of inspectable artifact files
  const ARTIFACT_FILES = [
    'manifest.json',
    'semantic_ir_program.json',
    'compilation_report.json',
    'diagnostics.json',
    'requirements.json',
    'classified_ast.json',
    'compatibility_metadata.json',
    'form_table.json',
    'form_resolution_trace.json'
  ]

  async function inspectFile(filename: string) {
    if (!selectedEvent.artifactDir) return
    selectedFile = filename
    fileContent = ''
    fileError = ''
    isLoadingFile = true
    try {
      const fullPath = `${selectedEvent.artifactDir}/${filename}`
      const content = await api.readFile(fullPath)
      // Format if JSON
      try {
        fileContent = JSON.stringify(JSON.parse(content), null, 2)
      } catch {
        fileContent = content
      }
    } catch (e) {
      fileError = `File '${filename}' is not present or could not be read.`
    } finally {
      isLoadingFile = false
    }
  }

  function formatTime(ts: number) {
    return new Date(ts).toLocaleTimeString([], { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })
  }

  function formatDate(ts: number) {
    return new Date(ts).toLocaleDateString([], { month: 'short', day: 'numeric' })
  }

  function handleReplayClick() {
    if (selectedEvent && selectedEvent.type === 'run') {
      dispatch('replay', {
        contractName: selectedEvent.contractName,
        inputs: selectedEvent.inputs
      })
    }
  }

  async function copyDebugBundle() {
    if (!selectedEvent) return

    const bundle: Record<string, any> = {
      event_id: selectedEvent.id,
      type: selectedEvent.type,
      contract: selectedEvent.contractName,
      timestamp: new Date(selectedEvent.timestamp).toISOString(),
      duration_ms: selectedEvent.durationMs,
      success: selectedEvent.success,
    }

    if (selectedEvent.type === 'compile') {
      bundle.source_length = selectedEvent.sourceLength
      bundle.source_hash = selectedEvent.sourceHash
      bundle.command = selectedEvent.command
      bundle.artifact_dir = selectedEvent.artifactDir
      bundle.error_stage = selectedEvent.errorStage

      if (selectedEvent.artifactDir) {
        // Try to read diagnostics and manifest files to include in bundle
        try {
          const diag = await api.readFile(`${selectedEvent.artifactDir}/diagnostics.json`)
          bundle.diagnostics = JSON.parse(diag)
        } catch {}
        try {
          const report = await api.readFile(`${selectedEvent.artifactDir}/compilation_report.json`)
          bundle.compilation_report = JSON.parse(report)
        } catch {}
      }
    } else {
      bundle.inputs = selectedEvent.inputs
      bundle.error = selectedEvent.error
      bundle.result = selectedEvent.result
      bundle.error_stage = selectedEvent.errorStage

      if (semanticLoopNode || compiledLoopNode) {
        bundle.loop_diagnostics = {
          semantic_node: semanticLoopNode,
          compiled_node: compiledLoopNode
        }
      }
    }

    try {
      await navigator.clipboard.writeText(JSON.stringify(bundle, null, 2))
      alert('Debug bundle copied to clipboard!')
    } catch {
      alert('Failed to copy debug bundle.')
    }
  }

  onMount(() => {
    // Select first event if present
    if (filteredEvents.length > 0) {
      selectedEventId = filteredEvents[0].id
    }
  })
</script>

<div class="flex h-full text-xs font-mono overflow-hidden select-text">
  <!-- Left panel: chronological event log -->
  <div class="w-80 shrink-0 border-r border-ink-line flex flex-col h-full bg-ink-1/40">
    <div class="p-2 border-b border-ink-line flex items-center justify-between shrink-0 bg-ink-1">
      <div class="flex items-center gap-1">
        <button
          on:click={() => filterType = 'all'}
          class="px-2 py-0.5 rounded transition-colors cursor-pointer {filterType === 'all' ? 'bg-ignite/15 text-ignite font-semibold' : 'text-warm/50 hover:text-warm-3'}"
        >All</button>
        <button
          on:click={() => filterType = 'compile'}
          class="px-2 py-0.5 rounded transition-colors cursor-pointer {filterType === 'compile' ? 'bg-ignite/15 text-ignite font-semibold' : 'text-warm/50 hover:text-warm-3'}"
        >Compiles</button>
        <button
          on:click={() => filterType = 'run'}
          class="px-2 py-0.5 rounded transition-colors cursor-pointer {filterType === 'run' ? 'bg-ignite/15 text-ignite font-semibold' : 'text-warm/50 hover:text-warm-3'}"
        >Runs</button>
      </div>

      <button
        on:click={() => { artifacts.clearDebugEvents(); selectedEventId = 'pinned-loop-regression' }}
        class="text-warm/40 hover:text-oof px-1.5 py-0.5 rounded transition-colors cursor-pointer"
        title="Clear run/compile history from store"
      >
        Clear
      </button>
    </div>

    <!-- Scrollable event log list -->
    <div class="flex-1 overflow-y-auto min-h-0">
      {#if filteredEvents.length === 0}
        <div class="p-4 text-center text-warm/40 italic">No events match filter.</div>
      {:else}
        {#each filteredEvents as e (e.id)}
          <!-- svelte-ignore a11y_click_events_have_key_events -->
          <!-- svelte-ignore a11y_no_static_element_interactions -->
          <div
            on:click={() => selectedEventId = e.id}
            class="px-3 py-2 border-b border-ink-line/30 cursor-pointer transition-all flex items-start gap-2.5
                   {selectedEventId === e.id ? 'bg-ignite/10 border-l-2 border-l-ignite' : 'hover:bg-ink-2 border-l-2 border-l-transparent'}"
          >
            <!-- Status indicator dot -->
            <span class="shrink-0 mt-1.5 w-1.5 h-1.5 rounded-full {e.success ? 'bg-core shadow-[0_0_6px_var(--color-core)]' : 'bg-oof shadow-[0_0_6px_var(--color-oof)]'}"></span>

            <div class="flex-1 min-w-0">
              <div class="flex items-center justify-between">
                <span class="font-mono font-medium text-warm-3 truncate">{e.contractName}</span>
                <span class="text-[10px] text-warm/40 font-sans tabular-nums shrink-0">{formatTime(e.timestamp)}</span>
              </div>
              <div class="flex items-center justify-between mt-0.5 text-[10px] text-warm/50">
                <span class="uppercase tracking-wider text-[9px] font-bold text-warm/40 flex items-center gap-1">
                  {#if e.type === 'compile'}
                    ��� compile
                  {:else}
                    ��� run
                  {/if}
                  {#if e.id === 'pinned-loop-regression'}
                    <span class="bg-ink-3 text-escape px-1.5 py-0.5 rounded text-[8px] tracking-normal font-normal">pinned fixture</span>
                  {/if}
                </span>
                <span class="tabular-nums font-mono text-warm/40">{e.durationMs}ms</span>
              </div>
              {#if !e.success}
                <div class="text-[10px] text-oof mt-1 truncate pl-1 font-mono leading-tight bg-oof/10 border-l border-oof/40 py-0.5 rounded-r">
                  {e.error || e.errorStage || 'Failed'}
                </div>
              {/if}
            </div>
          </div>
        {/each}
      {/if}
    </div>
  </div>

  <!-- Right panel: Event Details Inspector -->
  <div class="flex-1 flex flex-col h-full bg-ink-2/40 min-w-0">
    {#if !selectedEvent}
      <div class="flex flex-col items-center justify-center h-full text-warm/40 gap-2">
        <span class="text-4xl opacity-10">���</span>
        <span>Select an event to inspect compile/run metadata and artifacts</span>
      </div>
    {:else}
      <!-- Header -->
      <div class="px-4 py-2.5 border-b border-ink-line bg-ink-1 flex items-center justify-between shrink-0">
        <div class="min-w-0">
          <div class="flex items-center gap-2">
            <span class="text-sm font-mono font-bold text-warm-3 truncate">{selectedEvent.contractName}</span>
            <span class="px-1.5 py-0.5 rounded text-[10px] font-bold uppercase tracking-wider
                         {selectedEvent.success ? 'bg-core/10 text-core border border-core/30' : 'bg-oof/10 text-oof border border-oof/30'}">
              {selectedEvent.success ? 'Success' : 'Failure'}
            </span>
          </div>
          <div class="text-[10px] text-warm/40 mt-0.5 font-sans">
            Executed on {formatDate(selectedEvent.timestamp)} at {new Date(selectedEvent.timestamp).toLocaleTimeString()}
          </div>
        </div>

        <div class="flex items-center gap-2">
          {#if selectedEvent.type === 'run'}
            <button
              on:click={handleReplayClick}
              class="px-2.5 py-1 bg-core/15 hover:bg-core/25 text-core border border-core/20 rounded font-semibold transition-colors flex items-center gap-1 cursor-pointer"
              title="Load inputs into run panel and trigger execution"
            >
              ��� Replay
            </button>
          {/if}
          <button
            on:click={copyDebugBundle}
            class="px-2.5 py-1 bg-ink-3 hover:bg-ink-3/80 text-warm-3 border border-ink-line rounded font-semibold transition-colors flex items-center gap-1 cursor-pointer"
            title="Copy all telemetry and artifact data as a bundle"
          >
            ���� Copy Debug Bundle
          </button>
        </div>
      </div>

      <!-- Main Scrollable Details Container -->
      <div class="flex-1 overflow-y-auto min-h-0 p-4 space-y-4">

        <!-- SECTION 1: METADATA & TELEMETRY -->
        <div>
          <h3 class="text-[10px] font-bold text-warm/40 uppercase tracking-wider mb-2">Telemetry & Metadata</h3>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
            <div class="bg-ink-3 border border-ink-line/50 p-2 rounded">
              <div class="text-[10px] text-warm/40">Event Type</div>
              <div class="font-mono text-warm-3 uppercase mt-0.5 font-bold">{selectedEvent.type}</div>
            </div>
            <div class="bg-ink-3 border border-ink-line/50 p-2 rounded">
              <div class="text-[10px] text-warm/40">Duration</div>
              <div class="font-mono text-escape mt-0.5 font-semibold tabular-nums">{selectedEvent.durationMs}ms</div>
            </div>
            {#if selectedEvent.type === 'compile'}
              <div class="bg-ink-3 border border-ink-line/50 p-2 rounded">
                <div class="text-[10px] text-warm/40">Source Size</div>
                <div class="font-mono text-warm-3 mt-0.5 tabular-nums">{selectedEvent.sourceLength ?? '���'} B</div>
              </div>
              <div class="bg-ink-3 border border-ink-line/50 p-2 rounded min-w-0">
                <div class="text-[10px] text-warm/40 truncate">Source Hash (SHA-256)</div>
                <div class="font-mono text-warm/50 mt-0.5 truncate text-[10px]" title={selectedEvent.sourceHash}>
                  {selectedEvent.sourceHash ? selectedEvent.sourceHash.slice(0, 10) + '���' : '���'}
                </div>
              </div>
            {:else}
              <div class="bg-ink-3 border border-ink-line/50 p-2 rounded">
                <div class="text-[10px] text-warm/40">Likely Failure Stage</div>
                <div class="font-mono text-escape mt-0.5 font-semibold uppercase">{selectedEvent.errorStage ?? '���'}</div>
              </div>
              <div class="bg-ink-3 border border-ink-line/50 p-2 rounded">
                <div class="text-[10px] text-warm/40">Backend / Engine</div>
                <div class="font-mono text-warm/50 mt-0.5 uppercase">{selectedEvent.runtime ?? 'in_memory'}</div>
              </div>
            {/if}
          </div>
        </div>

        <!-- SECTION 1.5: CAPABILITY & SECURITY OBSERVABILITY (P10) -->
        {#if selectedEvent.type === 'run'}
          <div class="bg-ink-3 border border-ink-line/50 rounded p-4 space-y-4">
            <h3 class="text-[10px] font-bold text-warm/40 uppercase tracking-wider">I/O Capability & Security Observability</h3>

            <!-- 1. Stepper -->
            <div class="flex items-center justify-between bg-ink-1/40 p-3 rounded border border-ink-line/30">
              <span class="text-[10px] text-warm/50 font-bold uppercase">Boundary Phase:</span>
              <div class="flex items-center gap-2">
                <!-- Step 1: Compiler -->
                <div class="flex items-center gap-1.5">
                  <span class="w-4 h-4 rounded-full flex items-center justify-center text-[9px] font-bold
                               {selectedEvent.boundaryPhase === 'compiler' ? 'bg-oof/15 text-oof border border-oof/40' : 'bg-core/15 text-core border border-core/40'}">
                    {selectedEvent.boundaryPhase === 'compiler' ? '���' : '���'}
                  </span>
                  <span class="text-[10.5px] font-semibold {selectedEvent.boundaryPhase === 'compiler' ? 'text-oof' : 'text-core'}">Compiler</span>
                </div>

                <span class="text-warm/20">&rarr;</span>

                <!-- Step 2: Loader -->
                <div class="flex items-center gap-1.5">
                  {#if selectedEvent.boundaryPhase === 'compiler'}
                    <span class="w-4 h-4 rounded-full flex items-center justify-center text-[9px] bg-ink-2 text-warm/20 border border-ink-line">&bull;</span>
                    <span class="text-[10.5px] text-warm/30">Loader</span>
                  {:else if selectedEvent.boundaryPhase === 'loader'}
                    <span class="w-4 h-4 rounded-full flex items-center justify-center text-[9px] font-bold bg-oof/15 text-oof border border-oof/40">���</span>
                    <span class="text-[10.5px] font-semibold text-oof">Loader</span>
                  {:else}
                    <span class="w-4 h-4 rounded-full flex items-center justify-center text-[9px] font-bold bg-core/15 text-core border border-core/40">���</span>
                    <span class="text-[10.5px] font-semibold text-core">Loader</span>
                  {/if}
                </div>

                <span class="text-warm/20">&rarr;</span>

                <!-- Step 3: Execution -->
                <div class="flex items-center gap-1.5">
                  {#if selectedEvent.boundaryPhase === 'compiler' || selectedEvent.boundaryPhase === 'loader'}
                    <span class="w-4 h-4 rounded-full flex items-center justify-center text-[9px] bg-ink-2 text-warm/20 border border-ink-line">&bull;</span>
                    <span class="text-[10.5px] text-warm/30">Execution</span>
                  {:else if selectedEvent.boundaryPhase === 'execution'}
                    <span class="w-4 h-4 rounded-full flex items-center justify-center text-[9px] font-bold bg-oof/15 text-oof border border-oof/40">���</span>
                    <span class="text-[10.5px] font-semibold text-oof">Execution</span>
                  {:else}
                    <span class="w-4 h-4 rounded-full flex items-center justify-center text-[9px] font-bold bg-core/15 text-core border border-core/40">���</span>
                    <span class="text-[10.5px] font-semibold text-core">Execution</span>
                  {/if}
                </div>
              </div>
            </div>

            <!-- 2. Loader Decision Alert -->
            {#if selectedEvent.loaderDecision}
              {@const isApproved = selectedEvent.loaderDecision === 'approved'}
              <div class="p-3 rounded border flex items-start gap-2.5 backdrop-blur-sm
                           {isApproved ? 'bg-core/5 border-core/20 text-core/90' : 'bg-oof/5 border-oof/20 text-oof/90'}">
                <span class="text-xs">{isApproved ? '����' : '����'}</span>
                <div class="space-y-1">
                  <div class="font-bold text-[10.5px] uppercase tracking-wide">Loader Decision: {isApproved ? 'Approved' : 'Rejected'}</div>
                  <div class="text-[10.5px] leading-normal font-sans">
                    {#if isApproved}
                      Dynamic call capability bindings resolved and validated against active grants successfully.
                    {:else}
                      Contract loading blocked: {selectedEvent.loaderDecision}
                    {/if}
                  </div>
                </div>
              </div>
            {/if}

            <!-- 3. Passport Summary -->
            {#if selectedEvent.passportSummary}
              <div class="border border-ink-line/30 rounded overflow-hidden">
                <div class="bg-ink-1 px-3 py-1.5 border-b border-ink-line/30 text-[9px] font-bold uppercase tracking-wider text-warm/40 flex items-center justify-between">
                  <span>Capability Passport Summary</span>
                  <span class="bg-ink-3 text-escape px-1.5 py-0.5 rounded text-[8px] tracking-normal font-normal font-mono">v0 delegation</span>
                </div>
                <div class="p-3 space-y-3 bg-ink-2/30">
                  <div class="grid grid-cols-2 gap-2 text-[10.5px]">
                    <div><span class="text-warm/40">Runtime Target:</span> <code class="text-warm-3 font-mono">{selectedEvent.passportSummary.runtime_implementation_id || '���'}</code></div>
                    <div><span class="text-warm/40">Consumer Surface:</span> <code class="text-warm-3 font-mono">{selectedEvent.passportSummary.consumer_surface_id || '���'}</code></div>
                  </div>

                  {#if passportCapabilities(selectedEvent.passportSummary).length > 0}
                    <div class="space-y-1.5">
                      <div class="text-[9px] font-bold uppercase tracking-wide text-warm/40">Required Capabilities & Sandbox Bindings</div>
                      <div class="space-y-1">
                        {#each passportCapabilities(selectedEvent.passportSummary) as [cap_id, cap]}
                          {@const boundParam = boundParamFor(selectedEvent.passportSummary, cap_id)}
                          <div class="bg-ink-3 border border-ink-line/40 rounded p-2 text-[10.5px] space-y-1.5">
                            <div class="flex items-center justify-between">
                              <span class="font-bold text-ignite">{cap_id}</span>
                              <span class="text-warm/40 text-[9px]">bound to parameter: <code class="text-warm-3 font-mono">{boundParam}</code></span>
                            </div>
                            <div class="text-[10px] text-warm/50 font-sans truncate" title={cap.sandbox_dir || ''}>
                              ���� Sandbox: <code class="text-warm-3 font-mono">{cap.sandbox_dir || 'none'}</code>
                            </div>
                            <div class="flex items-center gap-3 text-[9.5px]">
                              <span class="flex items-center gap-1">
                                <span class="{cap.read_allowed ? 'text-core' : 'text-warm/30'}">{cap.read_allowed ? '���' : '���'}</span>
                                <span class="text-warm/50">read</span>
                              </span>
                              <span class="flex items-center gap-1">
                                <span class="{cap.write_allowed ? 'text-core' : 'text-warm/30'}">{cap.write_allowed ? '���' : '���'}</span>
                                <span class="text-warm/50">write</span>
                              </span>
                            </div>
                          </div>
                        {/each}
                      </div>
                    </div>
                  {/if}
                </div>
              </div>
            {/if}

            <!-- 4. FFI Observations / Receipts Log -->
            {#if selectedEvent.ffiObservations && selectedEvent.ffiObservations.length > 0}
              <div class="space-y-2">
                <div class="text-[10px] font-bold text-warm/40 uppercase tracking-wider">Captured FFI Observations & Receipts</div>
                <div class="space-y-1.5">
                  {#each selectedEvent.ffiObservations as obs}
                    {@const isRead = obs.kind === 'io_read_observation'}
                    <div class="bg-ink-3 border border-ink-line/50 rounded p-3 text-[10.5px] space-y-2">
                      <div class="flex items-center justify-between">
                        <span class="font-bold uppercase tracking-wider text-[9px] px-1.5 py-0.5 rounded
                                     {isRead ? 'bg-core/10 text-core border border-core/20' : 'bg-ember/10 text-ember border border-ember/20'}">
                          {isRead ? '���� Read Observation' : '��� Write Receipt'}
                        </span>
                        <span class="text-warm/40 text-[9.5px] font-sans">
                          {obs.observation_id || obs.receipt_id || '���'}
                        </span>
                      </div>

                      <div class="space-y-1 font-mono text-warm/70">
                        <div class="flex items-start gap-1">
                          <span class="text-warm/40 shrink-0 w-24">Target Path:</span>
                          <span class="text-warm-3 break-all">{obs.path || '���'}</span>
                        </div>
                        {#if isRead}
                          <div class="flex items-center gap-1">
                            <span class="text-warm/40 w-24">Bytes Read:</span>
                            <span class="text-temporal font-semibold">{obs.bytes_read ?? 0} B</span>
                          </div>
                        {:else}
                          <div class="flex items-center gap-1">
                            <span class="text-warm/40 w-24">Bytes Written:</span>
                            <span class="text-temporal font-semibold">{obs.bytes_written ?? 0} B</span>
                          </div>
                        {/if}
                        <div class="flex items-start gap-1">
                          <span class="text-warm/40 shrink-0 w-24">FNV-1a Digest:</span>
                          <span class="text-escape font-semibold break-all">{obs.content_digest || '���'}</span>
                        </div>
                        <div class="flex items-start gap-1">
                          <span class="text-warm/40 shrink-0 w-24">Active Grant:</span>
                          <span class="text-warm/50 break-all text-[9.5px]">{obs.delegation_chain || obs.capability_id || '���'}</span>
                        </div>
                      </div>
                    </div>
                  {/each}
                </div>
              </div>
            {/if}
          </div>
        {/if}

        <!-- SECTION 2: FAILURE SUMMARY & LIKELY STAGE DIAGNOSIS -->
        {#if !selectedEvent.success}
          <div class="bg-oof/10 border border-oof/20 rounded p-3.5 space-y-2">
            <div class="flex items-center gap-2 text-oof font-bold">
              <span>���</span>
              <span>Failure Context</span>
              {#if selectedEvent.errorStage}
                <span class="text-[9px] bg-oof/20 text-oof border border-oof/30 px-1.5 py-0.5 rounded uppercase tracking-wider font-semibold">Stage: {selectedEvent.errorStage}</span>
              {/if}
            </div>
            <pre class="font-mono text-oof/90 whitespace-pre-wrap break-all leading-normal text-[11px] bg-oof/5 p-2 border border-oof/20 rounded">{selectedEvent.error || ''}</pre>

            <!-- Diagnostics checklist -->
            {#if selectedEvent.diagnostics && selectedEvent.diagnostics.length > 0}
              <div class="mt-3 space-y-1.5 border-t border-oof/20 pt-3">
                <div class="text-[10px] font-bold text-oof uppercase tracking-wide">Static Capability Violations:</div>
                <div class="space-y-1">
                  {#each selectedEvent.diagnostics as diag}
                    <div class="bg-oof/5 border border-oof/20 rounded p-2 text-[10.5px] space-y-1 leading-normal">
                      <div class="flex items-center justify-between">
                        <span class="font-bold text-oof">{diag.rule}</span>
                        {#if diag.line}
                          <span class="text-warm/40 text-[9.5px]">line {diag.line}</span>
                        {/if}
                      </div>
                      <div class="text-warm/80 font-sans">{diag.message}</div>
                    </div>
                  {/each}
                </div>
              </div>
            {/if}

            <div class="text-[11px] text-warm/50 leading-relaxed font-sans">
              {#if selectedEvent.errorStage === 'parse'}
                <strong class="text-warm-3">Parse failure</strong>: The grammar or token stream is invalid. Check for missing keywords, block structure mismatches, or malformed syntax.
              {:else if selectedEvent.errorStage === 'classify'}
                <strong class="text-warm-3">Classification failure</strong>: Fragment boundary check failed. You may be mixing pure/observed nodes improperly or referencing symbols that do not match the contract type or modifiers.
              {:else if selectedEvent.errorStage === 'typecheck'}
                <strong class="text-warm-3">Type check failure</strong>: Mismatched types in node calculations (e.g. adding a String to an Integer). Verify the declared types on inputs and outputs.
              {:else if selectedEvent.errorStage === 'VM compile' || selectedEvent.errorStage === 'compiler'}
                <strong class="text-warm-3">VM compilation failure</strong>: The contract compiled successfully to SemanticIR but could not be translated into Compiled VM bytecode instructions.
              {:else if selectedEvent.errorStage === 'VM loader' || selectedEvent.errorStage === 'loader'}
                <strong class="text-warm-3">VM loader verification failure</strong>: Capability passport load-time validation failed (e.g., privilege escalation or signature digest tamper).
              {:else if selectedEvent.errorStage === 'VM run' || selectedEvent.errorStage === 'execution'}
                <strong class="text-warm-3">VM execution failure</strong>: An unhandled exception or contract validation check failed at runtime (e.g. sandbox path traversal escape).
              {/if}
            </div>
          </div>
        {/if}

        <!-- SECTION 3: LOOP REGRESSION & RESOLUTION DIAGNOSTICS -->
        {#if showLoopAnalysis}
          <div class="border rounded p-4 space-y-3
                      {loopResolutionStatus === 'resolved' ? 'border-core/20 bg-core/10' : 'border-escape/20 bg-escape/10'}">
            <div class="flex items-center justify-between">
              <span class="text-[10px] font-bold uppercase tracking-wider
                           {loopResolutionStatus === 'resolved' ? 'text-core' : 'text-escape'}">
                ���� Loop Mismatch Diagnostics
              </span>
              {#if loopDiagLoading}
                <span class="text-warm/40 animate-pulse text-[10px]">Loading AST nodes���</span>
              {:else}
                <span class="px-2 py-0.5 rounded text-[10px] font-bold uppercase tracking-wider
                             {loopResolutionStatus === 'resolved' ? 'bg-core/10 text-core border border-core/30' : 'bg-escape/10 text-escape border border-escape/30'}">
                  {loopResolutionStatus === 'resolved' ? 'Resolved' : 'Regression Active'}
                </span>
              {/if}
            </div>

            {#if loopDiagError}
              <div class="text-escape text-[11px] font-semibold">{loopDiagError}</div>
            {:else}
              {#if loopResolutionStatus === 'resolved'}
                <div class="text-[11px] text-warm/60 leading-relaxed font-sans bg-core/10 p-3 rounded border border-core/20">
                  <span class="text-core font-bold">��� Loop Mismatch Resolved:</span><br/>
                  The compiler assembler correctly outputs the loop node containing both <code>expr</code> and <code>body_nodes</code> properties in the final compiled JSON representation.<br/>
                  The VM loop compiler can successfully compile and run the loop collection expression.
                </div>
              {:else}
                <div class="text-[11px] text-warm/60 leading-relaxed font-sans bg-escape/10 p-3 rounded border border-escape/20">
                  <span class="text-escape font-bold">Impedance Mismatch Discovered:</span><br/>
                  The <code>igniter-vm</code> compiler expects the collection reference in the <code>expr</code> field of the loop node (e.g. <code>igniter-vm/src/compiler.rs:L337</code> parses <code>node.get("expr")</code>).<br/>
                  However, the compiler assembler (in <code>igniter-compiler/src/assembler.rs:L250</code>) renames the <code>expr</code> field to <code>expression</code> in the final compiled JSON contract representation and strips the <code>body_nodes</code>, causing a <code>Missing loop collection expr</code> error.
                </div>
              {/if}

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <!-- SemanticIR AST Loop Node -->
                <div>
                  <div class="text-[10px] text-warm/40 font-sans mb-1 font-bold">SemanticIR AST Loop Node (from AST/source)</div>
                  <pre class="bg-ink-3 border border-ink-line rounded p-2 text-[10px] leading-relaxed max-h-48 overflow-y-auto font-mono text-warm/70">
{#if semanticLoopNode}
{JSON.stringify(semanticLoopNode, null, 2)}
{:else}
(No loop node found in semantic_ir_program.json)
{/if}
                  </pre>
                  {#if semanticLoopNode}
                    <div class="flex items-center gap-1 text-[10px] mt-1 text-core font-medium">
                      <span>���</span> <code>expr</code> field is present (references <code>"{semanticLoopNode.expr?.name || 'items'}"</code>)
                    </div>
                  {/if}
                </div>

                <!-- Compiled IR Loop Node -->
                <div>
                  <div class="text-[10px] text-warm/40 font-sans mb-1 font-bold">Compiled IR Contract Loop Node (seen by VM)</div>
                  <pre class="bg-ink-3 border border-ink-line rounded p-2 text-[10px] leading-relaxed max-h-48 overflow-y-auto font-mono text-warm/70">
{#if compiledLoopNode}
{JSON.stringify(compiledLoopNode, null, 2)}
{:else}
(No loop node found in compiled contract file)
{/if}
                  </pre>
                  {#if compiledLoopNode}
                    {#if loopResolutionStatus === 'resolved'}
                      <div class="flex items-center gap-1 text-[10px] mt-1 text-core font-medium">
                        <span>���</span> <code>expr</code> and <code>body_nodes</code> are present and aligned!
                      </div>
                    {:else}
                      <div class="flex items-center gap-1 text-[10px] mt-1 text-oof font-medium">
                        <span>���</span> <code>expr</code> or <code>body_nodes</code> is missing or renamed!
                      </div>
                    {/if}
                  {/if}
                </div>
              </div>
            {/if}
          </div>
        {/if}

        <!-- SECTION 4: RUN INPUTS / OUTPUTS -->
        {#if selectedEvent.type === 'run'}
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <!-- Inputs -->
            <div class="flex flex-col">
              <span class="text-[10px] font-bold text-warm/40 uppercase tracking-wider mb-2">Inputs</span>
              <pre class="flex-1 bg-ink-3 border border-ink-line rounded p-3 overflow-x-auto min-h-24 max-h-64 text-[11px] leading-relaxed text-temporal font-mono">
{JSON.stringify(selectedEvent.inputs ?? {}, null, 2)}
              </pre>
            </div>

            <!-- Result -->
            <div class="flex flex-col">
              <span class="text-[10px] font-bold text-warm/40 uppercase tracking-wider mb-2">Result / Output</span>
              {#if selectedEvent.success}
                <pre class="flex-1 bg-ink-3 border border-ink-line rounded p-3 overflow-x-auto min-h-24 max-h-64 text-[11px] leading-relaxed text-core font-mono">
{JSON.stringify(selectedEvent.result, null, 2)}
                </pre>
              {:else}
                <div class="flex-1 bg-ink-3 border border-ink-line rounded p-3 min-h-24 max-h-64 text-[11px] text-oof leading-normal font-mono">
                  No outputs produced.<br/>
                  Execution failed with error: {selectedEvent.error}
                </div>
              {/if}
            </div>
          </div>
        {/if}

        <!-- SECTION 5: ARTIFACT FILE EXPLORER (COMPILE ONLY) -->
        {#if selectedEvent.type === 'compile' && selectedEvent.artifactDir}
          <div class="border border-ink-line rounded overflow-hidden">
            <div class="px-3 py-2 bg-ink-1 border-b border-ink-line flex items-center justify-between">
              <span class="text-[10px] font-bold text-warm/40 uppercase tracking-wider">Artifact Explorer</span>
              <span class="text-[9px] text-warm/40 truncate font-mono select-all max-w-lg" title={selectedEvent.artifactDir}>
                ���� {selectedEvent.artifactDir}
              </span>
            </div>

            <div class="flex h-72">
              <!-- Sidebar File List -->
              <div class="w-48 shrink-0 border-r border-ink-line bg-ink-1/50 overflow-y-auto">
                {#each ARTIFACT_FILES as file}
                  <button
                    on:click={() => inspectFile(file)}
                    class="w-full text-left px-3 py-1.5 border-b border-ink-line/30 transition-colors hover:bg-ink-2 truncate font-mono text-[10.5px] cursor-pointer
                           {selectedFile === file ? 'bg-ignite/10 text-ignite font-semibold' : 'text-warm/50'}"
                  >
                    ���� {file}
                  </button>
                {/each}
                <!-- Dynamic nested contracts support -->
                <button
                  on:click={() => inspectFile(`contracts/${selectedEvent.contractName.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase()}.json`)}
                  class="w-full text-left px-3 py-1.5 border-b border-ink-line/30 transition-colors hover:bg-ink-2 truncate font-mono text-[10.5px] cursor-pointer
                         {selectedFile.startsWith('contracts/') ? 'bg-ignite/10 text-ignite font-semibold' : 'text-warm/50'}"
                >
                  ���� contracts/{selectedEvent.contractName.toLowerCase()}.json
                </button>
              </div>

              <!-- Content Viewer -->
              <div class="flex-1 overflow-hidden relative bg-ink-3">
                {#if !selectedFile}
                  <div class="flex items-center justify-center h-full text-warm/40 italic select-none">
                    Select a compilation artifact from the list to inspect raw JSON
                  </div>
                {:else if isLoadingFile}
                  <div class="flex items-center justify-center h-full text-warm/40 gap-2 select-none">
                    <span class="animate-spin text-lg">���</span>
                    <span>Reading file content���</span>
                  </div>
                {:else if fileError}
                  <div class="p-4 text-escape font-semibold leading-normal">
                    {fileError}
                  </div>
                {:else}
                  <pre class="w-full h-full p-3 overflow-auto text-[11px] leading-relaxed text-warm-3 font-mono whitespace-pre">{fileContent}</pre>
                {/if}
              </div>
            </div>
          </div>
        {/if}

      </div>
    {/if}
  </div>
</div>
