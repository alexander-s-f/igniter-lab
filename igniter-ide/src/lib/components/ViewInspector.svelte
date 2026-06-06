<script lang="ts">
  import { onMount } from 'svelte'
  import { api } from '$lib/api'
  import type { WorkspaceConfig } from '$lib/types'
  import ViewNodeRenderer from './ViewNodeRenderer.svelte'
  import ViewTreeInspectorNode from './ViewTreeInspectorNode.svelte'
  import { sanitizeNode } from '$lib/safe_renderer_policy'
  import type { ViewNode } from '$lib/safe_renderer_policy'
  import { runVerificationProofs } from '$lib/gui_interaction_ir'

  interface DiagnosticEvent {
    timestamp: string
    kind: string
    message: string
    metadata?: Record<string, any>
  }

  interface TokenReport {
    artifact: string
    token_usage: Record<string, number>
  }

  // Svelte 5 props
  let { workspace }: { workspace: WorkspaceConfig | null } = $props()

  // Svelte 5 state variables
  let viewTreePath = $state('')
  let viewTree = $state<ViewNode | null>(null)
  let diagnosticsEvents = $state<DiagnosticEvent[]>([])
  let tokenUsage = $state<Record<string, number>>({})

  let selectedNode = $state<ViewNode | null>(null)
  let activeTab = $state<'diagnostics' | 'tokens'>('diagnostics')
  let loading = $state(false)
  let errorMsg = $state<string | null>(null)

  let lastRawTree = ''
  let reloadInterval: any = null

  // Initialize paths when workspace updates
  $effect(() => {
    if (workspace && !viewTreePath) {
      viewTreePath = `${workspace.root_dir}/igniter-view-engine/out/view_tree.json`
      loadArtifacts()
    }
  })

  // Watcher for hot reload (VSAFE-10)
  onMount(() => {
    // Run GUI IR verification proofs (TMX-P2-8)
    try {
      const proofRes = runVerificationProofs()
      const proofEvents = proofRes.log.map(msg => ({
        timestamp: new Date().toLocaleTimeString(),
        kind: proofRes.success ? 'compilation_complete' : 'safe_renderer_warning',
        message: msg
      }))
      diagnosticsEvents = [...proofEvents, ...diagnosticsEvents]
    } catch (err) {
      console.error('Failed to run verification proofs:', err)
    }

    reloadInterval = setInterval(() => {
      if (workspace && viewTreePath && !loading) {
        reloadTreeSilently()
      }
    }, 1500)

    return () => {
      clearInterval(reloadInterval)
    }
  })

  async function reloadTreeSilently() {
    try {
      const rawTree = await api.readFile(viewTreePath)
      if (rawTree === lastRawTree) return // No changes

      lastRawTree = rawTree

      let newTree: ViewNode
      try {
        newTree = JSON.parse(rawTree)
      } catch (err: any) {
        // Fail-closed with visible hot-reload parse errors (VCON-8)
        errorMsg = `Malformed Hot-Reload: Failed to parse view_tree.json.\n\nError: ${err?.message || err}`
        viewTree = null
        selectedNode = null
        return
      }

      errorMsg = null // clear previous errors
      viewTree = newTree
      initializeUIState(newTree)

      // Reload diagnostics and token report
      const baseDir = viewTreePath.substring(0, viewTreePath.lastIndexOf('/'))
      try {
        const rawDiag = await api.readFile(`${baseDir}/diagnostics.json`)
        const diagObj = JSON.parse(rawDiag)
        diagnosticsEvents = diagObj.events || []
      } catch {}

      try {
        const rawTokens = await api.readFile(`${baseDir}/token_usage_report.json`)
        const tokenObj = JSON.parse(rawTokens)
        tokenUsage = tokenObj.token_usage || {}
      } catch {}

      // Scan and inject safety policy alerts (VCON-2, VCON-6)
      scanTreeAndAppendDiagnostics(newTree)

      // Maintain selection or select root
      if (!selectedNode) selectedNode = viewTree

    } catch (err) {
      // Don't crash during background reload
    }
  }

  function scanTreeAndAppendDiagnostics(node: ViewNode) {
    const warnings: string[] = []

    const walk = (n: ViewNode, isRoot: boolean) => {
      const sanitized = sanitizeNode(n, isRoot)
      if (sanitized.warnings) {
        warnings.push(...sanitized.warnings)
      }
      n.children?.forEach(c => {
        if (typeof c === 'object') walk(c, false)
      })
    }

    walk(node, true)

    // Add unique warnings to timeline
    warnings.forEach(w => {
      if (!diagnosticsEvents.some(e => e.message === w)) {
        diagnosticsEvents.unshift({
          timestamp: new Date().toLocaleTimeString(),
          kind: 'safe_renderer_warning',
          message: w
        })
      }
    })
  }

  async function loadArtifacts() {
    if (!viewTreePath) {
      errorMsg = 'Please specify a path to view_tree.json'
      return
    }

    loading = true
    errorMsg = null
    viewTree = null
    diagnosticsEvents = []
    tokenUsage = {}
    selectedNode = null

    try {
      // 1. Load view tree
      let rawTree = ''
      try {
        rawTree = await api.readFile(viewTreePath)
      } catch (err) {
        errorMsg = `Missing Artifact: Failed to read view tree at:\n${viewTreePath}\n\nMake sure the view engine has run and generated this file.`
        loading = false
        return
      }

      lastRawTree = rawTree

      // 2. Parse view tree
      try {
        viewTree = JSON.parse(rawTree)
      } catch (err: any) {
        errorMsg = `Malformed Artifact: Failed to parse view_tree.json.\n\nError: ${err?.message || err}`
        loading = false
        return
      }

      // 3. Load diagnostics (try same folder)
      const baseDir = viewTreePath.substring(0, viewTreePath.lastIndexOf('/'))
      const diagPath = `${baseDir}/diagnostics.json`
      try {
        const rawDiag = await api.readFile(diagPath)
        const diagObj = JSON.parse(rawDiag)
        diagnosticsEvents = diagObj.events || []
      } catch (err) {
        console.warn('Could not load diagnostics.json:', err)
      }

      // 4. Load token usage report
      const tokenPath = `${baseDir}/token_usage_report.json`
      try {
        const rawTokens = await api.readFile(tokenPath)
        const tokenObj = JSON.parse(rawTokens) as TokenReport
        tokenUsage = tokenObj.token_usage || {}
      } catch (err) {
        console.warn('Could not load token_usage_report.json:', err)
      }

      // Scan tree and inject warning logs (VCON-2, VCON-6)
      if (viewTree) {
        scanTreeAndAppendDiagnostics(viewTree)
        initializeUIState(viewTree)
      }

      // Auto-select root node
      if (viewTree) selectedNode = viewTree

    } catch (err: any) {
      errorMsg = `An unexpected error occurred: ${err?.message || err}`
    } finally {
      loading = false
    }
  }

  // Active UIState (VDSL-IR-3)
  let activeUIState = $state<Record<string, any>>({})

  // Initialize UI State from defaults (VDSL-IR-3)
  function initializeUIState(node: ViewNode) {
    const statePatch: Record<string, any> = {}
    const walk = (n: ViewNode) => {
      if (n.ui_states) {
        for (const [k, v] of Object.entries(n.ui_states)) {
          statePatch[k] = v
        }
      }
      n.children?.forEach(c => {
        if (typeof c === 'object') walk(c)
      })
    }
    walk(node)
    activeUIState = statePatch
  }

  // Safe UI Interaction rule evaluator integration (VDSL-IR-7)
  import { evaluateInteractionRule } from '$lib/gui_interaction_ir'

  function handleTriggerInteraction(node: ViewNode, eventName: string) {
    if (!node.interaction_rules) return

    const rule = node.interaction_rules.find((r: any) => r[0] === eventName)
    if (!rule) return

    const res = evaluateInteractionRule(rule, {}, activeUIState, {}, node.node_params || {})

    // Log diagnostics events
    res.diagnostics.forEach(diag => {
      diagnosticsEvents.unshift({
        timestamp: new Date().toLocaleTimeString(),
        kind: diag.severity === 'error' ? 'safe_renderer_warning' : 'conditional_check',
        message: `Interaction: ${diag.message}`
      })
    })

    if (res.success && res.mutatedUiState) {
      activeUIState = res.mutatedUiState

      diagnosticsEvents.unshift({
        timestamp: new Date().toLocaleTimeString(),
        kind: 'conditional_check',
        message: `State Transition: activeUIState -> ${JSON.stringify(activeUIState)}`
      })
    }
  }

  function handleSelectNode(node: ViewNode) {
    selectedNode = node
  }
</script>

<div class="flex flex-col w-full h-full min-h-0 bg-ink text-warm-3 font-mono">

  <!-- Top Bar Controls -->
  <div class="flex items-center gap-2 px-3 py-2 border-b border-ink-line bg-ink-1 shrink-0">
    <span class="text-xs text-warm select-none">Path:</span>
    <input
      type="text"
      bind:value={viewTreePath}
      placeholder="/path/to/igniter-view-engine/out/view_tree.json"
      class="flex-1 bg-ink border border-ink-line rounded px-2 py-1 text-xs text-grey-3 font-mono h-7 min-w-0"
    />
    <button
      onclick={loadArtifacts}
      disabled={loading}
      class="h-7 px-3 bg-ignite/15 hover:bg-ignite/25 border border-ignite/30 text-ignite rounded text-xs font-semibold cursor-pointer shrink-0 transition-colors flex items-center gap-1.5"
    >
      {#if loading}
        <span class="animate-pulse">��� Loading...</span>
      {:else}
        <span>��� Refresh</span>
      {/if}
    </button>
  </div>

  <!-- Workspace warning empty state -->
  {#if !workspace}
    <div class="flex-1 flex flex-col items-center justify-center p-8 text-center bg-ink-1">
      <span class="text-4xl mb-3">����</span>
      <h3 class="text-warm-3 font-bold mb-1">No Active Workspace</h3>
      <p class="text-xs text-warm max-w-sm">Please open a workspace directory first to load view engine artifacts automatically.</p>
    </div>

  <!-- Error / Missing State -->
  {:else if errorMsg}
    <div class="flex-1 flex flex-col items-center justify-center p-8 bg-ink-1 overflow-auto">
      <div class="max-w-xl w-full border border-oof/40 bg-oof/5 p-6 rounded-lg shadow-lg relative reg">
        <div class="tr"></div>
        <div class="bl"></div>
        <h3 class="text-oof font-bold flex items-center gap-2 mb-3">
          <span>������</span>
          <span>Artifact Load Error</span>
        </h3>
        <pre class="text-xs text-warm-3 bg-ink p-4 rounded border border-ink-line whitespace-pre-wrap font-mono leading-relaxed max-h-96 overflow-y-auto">{errorMsg}</pre>
        <button
          onclick={loadArtifacts}
          class="mt-4 bg-oof text-ink-1 font-bold font-mono text-xs px-3 py-1.5 rounded cursor-pointer hover:opacity-90 transition-opacity"
        >
          Try Again
        </button>
      </div>
    </div>

  <!-- Main Split Layout -->
  {:else if viewTree}
    <div class="flex-1 flex min-h-0 overflow-hidden divide-x divide-ink-line">

      <!-- Left Column: Safe Structured HTML/Component Preview -->
      <div class="w-1/2 flex flex-col min-h-0 bg-ink-1 overflow-hidden">
        <div class="px-3 py-1.5 border-b border-ink-line bg-ink-2 shrink-0 flex justify-between items-center select-none">
          <span class="text-xs font-bold text-warm uppercase tracking-wider">Structured Preview</span>
          <span class="text-[9px] text-warm/40 font-mono bg-ink-1 border border-ink-line px-1.5 rounded">Safe Sandbox</span>
        </div>
        <div class="flex-1 p-6 overflow-y-auto ig-field">
          <div class="max-w-2xl mx-auto bg-ink-1 border border-ink-line rounded-lg shadow-xl p-6 relative">
            <ViewNodeRenderer
              node={viewTree}
              onSelectNode={handleSelectNode}
              {selectedNode}
              isRoot={true}
              {activeUIState}
              onTriggerInteraction={handleTriggerInteraction}
            />
          </div>
        </div>
      </div>

      <!-- Right Column: Inspector Tree, Node details & Logs -->
      <div class="w-1/2 flex flex-col min-h-0 divide-y divide-ink-line">

        <!-- Top Half: AST Inspector Tree & Details -->
        <div class="h-3/5 flex min-h-0 divide-x divide-ink-line">

          <!-- AST Tree Walker -->
          <div class="w-1/2 flex flex-col min-h-0">
            <div class="px-3 py-1.5 border-b border-ink-line bg-ink-2 shrink-0 flex items-center justify-between select-none">
              <span class="text-xs font-bold text-warm uppercase tracking-wider">AST Inspector Tree</span>
            </div>
            <div class="flex-1 p-2 overflow-y-auto bg-ink min-h-0">
              <ViewTreeInspectorNode node={viewTree} onSelectNode={handleSelectNode} {selectedNode} depth={0} />
            </div>
          </div>

          <!-- Selected Node Details -->
          <div class="w-1/2 flex flex-col min-h-0 bg-ink-1">
            <div class="px-3 py-1.5 border-b border-ink-line bg-ink-2 shrink-0 select-none">
              <span class="text-xs font-bold text-warm uppercase tracking-wider">Node Details</span>
            </div>
            <div class="flex-1 p-4 overflow-y-auto text-xs space-y-4">
              {#if selectedNode}
                <!-- Details block -->
                <div>
                  <span class="text-grey font-mono block mb-1">Tag/Type:</span>
                  <span class="text-warm-3 bg-ink border border-ink-line px-2 py-1 rounded font-mono text-sm block">
                    {selectedNode.tag === 'component' ? `��� Component (${selectedNode.component_name})` : `<${selectedNode.tag}>`}
                  </span>
                </div>

                {#if selectedNode.is_component}
                  <div>
                    <span class="text-grey font-mono block mb-1">Component Name:</span>
                    <span class="text-ignite font-bold font-mono block">{selectedNode.component_name}</span>
                  </div>
                {/if}

                <!-- Trace metadata (VID-4, VID-5) -->
                {#if selectedNode.trace_metadata}
                  <div>
                    <span class="text-grey font-mono block mb-1">Trace Context Path:</span>
                    {#if selectedNode.trace_metadata.context && selectedNode.trace_metadata.context.length > 0}
                      <div class="flex flex-wrap gap-1 mt-1">
                        {#each selectedNode.trace_metadata.context as ctx}
                          <span class="bg-ink border border-ink-line text-temporal text-[10px] px-1.5 py-0.5 rounded font-mono">
                            {ctx}
                          </span>
                        {/each}
                      </div>
                    {:else}
                      <span class="text-grey/40 italic">Root scope</span>
                    {/if}
                  </div>

                  {#if selectedNode.trace_metadata.forms_assisted}
                    <div class="border border-amber/30 bg-amber/5 p-2 rounded relative">
                      <span class="text-amber font-bold block text-[10px] mb-1">������ DX CANDIDATE ONLY</span>
                      <p class="text-[10px] text-grey-2 leading-relaxed">This view node was invoked using forms-assisted syntax. Forms are evaluated statically at compile time and do not imply runtime framework dispatch.</p>
                    </div>
                  {/if}

                  {#if selectedNode.trace_metadata.warnings}
                    <div class="border border-oof/30 bg-oof/5 p-3 rounded relative">
                      <span class="text-oof font-bold block text-[10px] mb-1">������ POLICY WARNINGS</span>
                      <ul class="list-disc pl-4 text-[10px] text-grey-2 space-y-1">
                        {#each selectedNode.trace_metadata.warnings as w}
                          <li>{w}</li>
                        {/each}
                      </ul>
                    </div>
                  {/if}
                {/if}
                <!-- State Slots (VSLOT-1) -->
                {#if selectedNode.state_slots && selectedNode.state_slots.length > 0}
                  <div>
                    <span class="text-grey font-mono block mb-1">State Slots:</span>
                    <div class="space-y-2">
                      {#each selectedNode.state_slots as slot}
                        <div class="bg-ink border border-temporal/30 p-2.5 rounded text-[11px] relative">
                          <div class="flex justify-between items-center mb-1 select-none">
                            <span class="text-temporal font-bold font-mono">��� {slot.slot_id}</span>
                            <span class="text-[9px] bg-temporal/10 text-temporal border border-temporal/25 px-1 rounded uppercase">{slot.value_kind}</span>
                          </div>
                          <div class="text-[10px] text-grey-2 space-y-0.5 font-mono">
                            <div><span class="text-grey">Ref:</span> <code class="text-warm-3">{slot.contract_output_ref}</code></div>
                            <div><span class="text-grey">Policy:</span> <code class="text-warm-3">{slot.render_policy}</code></div>
                            <div><span class="text-grey">Fallback:</span> <code class="text-warm-3">{JSON.stringify(slot.fallback)}</code></div>
                          </div>
                        </div>
                      {/each}
                    </div>
                  </div>
                {/if}

                <!-- UI State Defaults (VDSL-IR-3) -->
                {#if selectedNode.ui_states && Object.keys(selectedNode.ui_states).length > 0}
                  <div>
                    <span class="text-grey font-mono block mb-1">UI State Defaults:</span>
                    <div class="bg-ink border border-ignite/30 p-2.5 rounded text-[11px] space-y-1">
                      {#each Object.entries(selectedNode.ui_states) as [k, v]}
                        <div class="font-mono text-[10px] text-grey-2">
                          <span class="text-ignite font-bold">{k}:</span> <code class="text-warm-3">{JSON.stringify(v)}</code>
                        </div>
                      {/each}
                    </div>
                  </div>
                {/if}

                <!-- Active UIState Monitor -->
                {#if selectedNode.ui_states && Object.keys(selectedNode.ui_states).length > 0}
                  <div>
                    <span class="text-grey font-mono block mb-1">Active UIState Values:</span>
                    <div class="bg-ink border border-ignite/30 p-2.5 rounded text-[11px] space-y-1">
                      {#each Object.keys(selectedNode.ui_states) as k}
                        <div class="font-mono text-[10px] text-grey-2">
                          <span class="text-ignite font-bold">{k}:</span> <code class="text-core font-bold">{JSON.stringify(activeUIState[k])}</code>
                        </div>
                      {/each}
                    </div>
                  </div>
                {/if}

                <!-- Display Rules (VDSL-IR-1) -->
                {#if selectedNode.display_rules && selectedNode.display_rules.length > 0}
                  <div>
                    <span class="text-grey font-mono block mb-1">Display Rules:</span>
                    <div class="space-y-1.5">
                      {#each selectedNode.display_rules as rule}
                        <div class="bg-ink border border-line p-2 rounded text-[10px] font-mono leading-relaxed">
                          <pre class="text-grey-3 whitespace-pre-wrap">{JSON.stringify(rule, null, 2)}</pre>
                        </div>
                      {/each}
                    </div>
                  </div>
                {/if}

                <!-- Interaction Rules (VDSL-IR-2) -->
                {#if selectedNode.interaction_rules && selectedNode.interaction_rules.length > 0}
                  <div>
                    <span class="text-grey font-mono block mb-1">Interaction Rules:</span>
                    <div class="space-y-1.5">
                      {#each selectedNode.interaction_rules as rule}
                        <div class="bg-ink border border-line p-2 rounded text-[10px] font-mono leading-relaxed">
                          <div class="text-amber font-bold mb-1">on: {rule[0]}</div>
                          <pre class="text-grey-3 whitespace-pre-wrap">{JSON.stringify(rule[1], null, 2)}</pre>
                        </div>
                      {/each}
                    </div>
                  </div>
                {/if}

                <!-- Node Params (VDSL-IR-6) -->
                {#if selectedNode.node_params && Object.keys(selectedNode.node_params).length > 0}
                  <div>
                    <span class="text-grey font-mono block mb-1">Node Params:</span>
                    <div class="bg-ink border border-line p-2 rounded text-[10px] font-mono">
                      {#each Object.entries(selectedNode.node_params) as [k, v]}
                        <div><span class="text-grey">{k}:</span> <code class="text-warm-3">{JSON.stringify(v)}</code></div>
                      {/each}
                    </div>
                  </div>
                {/if}

                <!-- Attributes -->
                <div>
                  <span class="text-grey font-mono block mb-1">Attributes:</span>
                  {#if selectedNode.attributes && Object.keys(selectedNode.attributes).length > 0}
                    <div class="bg-ink border border-ink-line rounded overflow-hidden">
                      <table class="w-full text-left font-mono text-xs">
                        <thead>
                          <tr class="bg-ink-2 border-b border-ink-line text-grey">
                            <th class="px-2 py-1 font-normal">Key</th>
                            <th class="px-2 py-1 font-normal">Value</th>
                          </tr>
                        </thead>
                        <tbody class="divide-y divide-ink-line text-grey-3">
                          {#each Object.entries(selectedNode.attributes) as [k, v]}
                            <tr>
                              <td class="px-2 py-1 text-grey font-mono">{k}</td>
                              <td class="px-2 py-1 break-all">{v}</td>
                            </tr>
                          {/each}
                        </tbody>
                      </table>
                    </div>
                  {:else}
                    <span class="text-grey/40 italic">No attributes</span>
                  {/if}
                </div>
              {:else}
                <div class="text-warm/40 italic text-center py-8">Select a node to inspect</div>
              {/if}
            </div>
          </div>
        </div>

        <!-- Bottom Half: Logs & Token Reports -->
        <div class="h-2/5 flex flex-col min-h-0 bg-ink overflow-hidden">

          <!-- Tabs selection bar -->
          <div class="flex border-b border-ink-line bg-ink-2 shrink-0 select-none">
            <button
              onclick={() => activeTab = 'diagnostics'}
              class="px-4 py-1.5 text-xs font-mono font-bold transition-colors cursor-pointer {activeTab === 'diagnostics' ? 'text-ignite border-b border-ignite bg-ink' : 'text-warm hover:text-warm-3'}"
            >
              Diagnostics Timeline
            </button>
            <button
              onclick={() => activeTab = 'tokens'}
              class="px-4 py-1.5 text-xs font-mono font-bold transition-colors cursor-pointer {activeTab === 'tokens' ? 'text-ignite border-b border-ignite bg-ink' : 'text-warm hover:text-warm-3'}"
            >
              Token Usage Report
            </button>
          </div>

          <!-- Tabs content container -->
          <div class="flex-1 overflow-y-auto p-3 min-h-0 bg-ink-1">

            <!-- Diagnostics Timeline tab -->
            {#if activeTab === 'diagnostics'}
              {#if diagnosticsEvents.length === 0}
                <div class="text-warm/40 italic text-center py-6 text-xs">No diagnostic events found.</div>
              {:else}
                <div class="space-y-3 font-mono text-xs">
                  {#each diagnosticsEvents as ev}
                    <div class="border border-ink-line bg-ink p-2 rounded flex flex-col gap-1 relative pl-6">
                      <!-- Left bullet indicator -->
                      <span class="absolute left-2.5 top-3.5 w-1.5 h-1.5 rounded-full
                        {ev.kind === 'conditional_check' ? 'bg-temporal' : ''}
                        {ev.kind === 'conditional_skip' ? 'bg-grey' : ''}
                        {ev.kind === 'loop_execution' ? 'bg-core' : ''}
                        {ev.kind === 'component_invocation' ? 'bg-ignite' : ''}
                        {ev.kind === 'forms_assisted_invocation' ? 'bg-amber' : ''}
                        {ev.kind === 'compilation_complete' ? 'bg-core' : ''}
                        {ev.kind === 'safe_renderer_warning' ? 'bg-oof animate-pulse' : ''}
                      "></span>

                      <div class="flex justify-between items-center text-[10px]">
                        <span class="text-grey">{ev.timestamp.split(' ').slice(1,2).join('') || ev.timestamp}</span>
                        <span class="text-[9px] px-1 rounded uppercase tracking-wider
                          {ev.kind === 'conditional_check' ? 'bg-temporal/15 text-temporal' : ''}
                          {ev.kind === 'conditional_skip' ? 'bg-grey/15 text-grey' : ''}
                          {ev.kind === 'loop_execution' ? 'bg-core/15 text-core' : ''}
                          {ev.kind === 'component_invocation' ? 'bg-ignite/15 text-ignite' : ''}
                          {ev.kind === 'forms_assisted_invocation' ? 'bg-amber/15 text-amber' : ''}
                          {ev.kind === 'compilation_complete' ? 'bg-core/20 text-core font-bold' : ''}
                          {ev.kind === 'safe_renderer_warning' ? 'bg-oof/15 text-oof font-bold' : 'bg-grey/10 text-grey'}
                        ">{ev.kind.replace(/_/g, ' ')}</span>
                      </div>
                      <span class="text-grey-3 font-sans mt-0.5">{ev.message}</span>
                      {#if ev.metadata && Object.keys(ev.metadata).length > 0}
                        <pre class="bg-ink-1 text-[10px] text-grey p-1.5 rounded border border-ink-line/60 mt-1 whitespace-pre-wrap overflow-x-auto max-h-24">{JSON.stringify(ev.metadata)}</pre>
                      {/if}
                    </div>
                  {/each}
                </div>
              {/if}

            <!-- Token Usage Report Tab -->
            {:else if activeTab === 'tokens'}
              {#if Object.keys(tokenUsage).length === 0}
                <div class="text-warm/40 italic text-center py-6 text-xs">No CSS classes recorded in report.</div>
              {:else}
                <div class="grid grid-cols-2 gap-2 font-mono text-xs">
                  {#each Object.entries(tokenUsage) as [cls, count]}
                    <div class="flex justify-between items-center bg-ink border border-ink-line p-2 rounded">
                      <span class="text-grey-3 truncate max-w-40" title={cls}>
                        <span class="text-grey">.</span>{cls}
                      </span>
                      <span class="text-[10px] bg-ink-2 text-warm border border-ink-line px-1.5 py-0.5 rounded font-bold">
                        {count}x
                      </span>
                    </div>
                  {/each}
                </div>
              {/if}
            {/if}

          </div>
        </div>

      </div>
    </div>
  {:else}
    <div class="flex-1 flex flex-col items-center justify-center p-8 text-center bg-ink-1">
      <span class="text-4xl mb-3">����</span>
      <h3 class="text-warm-3 font-bold mb-1">View Tree Preview</h3>
      <p class="text-xs text-warm max-w-sm mb-4">Load view tree artifacts to launch the safe preview sandbox and inspect components.</p>
      <button
        onclick={loadArtifacts}
        class="bg-ignite text-ink-1 font-bold font-mono text-xs px-4 py-2 rounded cursor-pointer hover:opacity-90 transition-opacity"
      >
        Load Artifacts
      </button>
    </div>
  {/if}

</div>

<style>
  /* Local scrollbar overrides for premium styling */
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
