<script lang="ts">
  import { onMount } from 'svelte'
  import { createEventDispatcher } from 'svelte'
  import { api } from '$lib/api'

  const dispatch = createEventDispatcher<{
    dispatched: void
  }>()

  // State inputs
  let transactionId = ''
  let producerId = 'ruby-vm-runner-v1.0'
  let signature = 'valid-mock-signature'

  // Outcome status display
  let lastScenario = ''
  let isDispatching = false
  let commandOutcome: 'Ok' | 'Err' | null = null
  let outcomeClassification = ''
  let lastErrorMessage = ''
  let receivedReceipt: any = null

  function generateTxId() {
    transactionId = 'tx_mock_' + Math.random().toString(36).substring(2, 11)
  }

  onMount(() => {
    generateTxId()
  })

  async function triggerMockDispatch(scenario: string) {
    if (isDispatching) return
    isDispatching = true
    commandOutcome = null
    outcomeClassification = ''
    lastErrorMessage = ''
    lastScenario = scenario
    receivedReceipt = null

    // Prepare variables for the call
    let targetStatus = scenario
    let targetSignature = signature
    let targetProducer = producerId

    if (scenario === 'invalid_signature') {
      targetStatus = 'applied'
      targetSignature = 'invalid-signature'
    } else if (scenario === 'unknown_status') {
      targetStatus = 'crash_and_burn'
    }

    try {
      const receipt = await api.runMockVmRunnerDispatch(
        transactionId,
        targetStatus,
        targetProducer,
        targetSignature
      )

      commandOutcome = 'Ok'
      receivedReceipt = receipt

      if (targetStatus === 'applied') {
        outcomeClassification = 'Ok (verified-applied)'
      } else {
        outcomeClassification = 'Ok (verified-non-applied)'
      }
    } catch (err) {
      commandOutcome = 'Err'
      outcomeClassification = 'Err (ingress rejected)'
      lastErrorMessage = String(err)
    } finally {
      isDispatching = false
      // Always notify parent to refresh telemetry history, since even failed dispatches log stubs
      dispatch('dispatched')
      // Auto-generate new transaction ID for the next attempt
      generateTxId()
    }
  }
</script>

<div class="bg-gray-950 border border-gray-800 rounded-lg p-4 font-mono text-xs text-gray-400 space-y-4 shrink-0">
  <!-- Lab-only warning banner -->
  <div class="flex items-center justify-between border-b border-gray-900 pb-2">
    <div class="flex items-center gap-2">
      <span class="px-2 py-0.5 rounded text-[10px] font-bold bg-amber-950/60 text-amber-400 border border-amber-800 uppercase tracking-wider">
        Lab-Only / Mock-Only
      </span>
      <span class="text-gray-300 font-bold text-sm">Telemetry Control Panel</span>
    </div>
    <span class="text-gray-600 text-[10px]">TIVF-P17 v0.1.0</span>
  </div>

  <p class="text-[11px] text-gray-500 leading-relaxed">
    Trigger mock VM runner scenarios directly from the browser to inspect the reactive trace adapter and redacted timeline updates.
    No network, watcher, or live execution will be performed.
  </p>

  <!-- Inputs Panel -->
  <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
    <div class="flex flex-col gap-1">
      <label for="mock-tx-id" class="text-gray-500 text-[10px] uppercase font-bold">Transaction ID</label>
      <div class="flex gap-1">
        <input
          id="mock-tx-id"
          type="text"
          bind:value={transactionId}
          placeholder="tx_mock_xxxxx"
          class="flex-1 bg-gray-900 border border-gray-800 rounded px-2.5 py-1.5 text-xs text-gray-200 focus:outline-none focus:border-yellow-500"
        />
        <button
          id="mock-btn-regenerate"
          on:click={generateTxId}
          class="px-2 bg-gray-900 border border-gray-800 hover:bg-gray-800 rounded text-gray-400 transition-colors"
          title="Regenerate Transaction ID"
        >
          🔄
        </button>
      </div>
    </div>

    <div class="flex flex-col gap-1">
      <label for="mock-producer-id" class="text-gray-500 text-[10px] uppercase font-bold">Producer ID</label>
      <input
        id="mock-producer-id"
        type="text"
        bind:value={producerId}
        placeholder="ruby-vm-runner-v1.0"
        class="bg-gray-900 border border-gray-800 rounded px-2.5 py-1.5 text-xs text-gray-200 focus:outline-none focus:border-yellow-500"
      />
    </div>

    <div class="flex flex-col gap-1">
      <label for="mock-signature" class="text-gray-500 text-[10px] uppercase font-bold">Passport Signature</label>
      <input
        id="mock-signature"
        type="text"
        bind:value={signature}
        placeholder="valid-mock-signature"
        class="bg-gray-900 border border-gray-800 rounded px-2.5 py-1.5 text-xs text-gray-200 focus:outline-none focus:border-yellow-500"
      />
    </div>
  </div>

  <!-- Scenario Buttons Matrix -->
  <div class="space-y-2">
    <div class="text-gray-500 text-[10px] uppercase font-bold">Runner Scenarios</div>
    <div class="flex flex-wrap gap-2">
      <!-- OK: Applied -->
      <button
        id="mock-scenario-applied"
        on:click={() => triggerMockDispatch('applied')}
        disabled={isDispatching}
        class="px-3 py-2 bg-emerald-950/40 border border-emerald-900/60 hover:bg-emerald-950/70 disabled:bg-gray-900 disabled:border-gray-800 rounded text-emerald-400 font-semibold transition-all flex flex-col items-start gap-0.5"
      >
        <span class="text-xs">applied</span>
        <span class="text-[9px] text-emerald-600 font-normal">Ok: verified-applied</span>
      </button>

      <!-- OK: Non-Applied -->
      <button
        id="mock-scenario-exec-failed"
        on:click={() => triggerMockDispatch('execution_failed')}
        disabled={isDispatching}
        class="px-3 py-2 bg-yellow-950/30 border border-yellow-900/50 hover:bg-yellow-950/50 disabled:bg-gray-900 disabled:border-gray-800 rounded text-yellow-400 font-semibold transition-all flex flex-col items-start gap-0.5"
      >
        <span class="text-xs">execution_failed</span>
        <span class="text-[9px] text-yellow-600 font-normal">Ok: non-applied</span>
      </button>

      <button
        id="mock-scenario-diag-only"
        on:click={() => triggerMockDispatch('diagnostic_only')}
        disabled={isDispatching}
        class="px-3 py-2 bg-yellow-950/30 border border-yellow-900/50 hover:bg-yellow-950/50 disabled:bg-gray-900 disabled:border-gray-800 rounded text-yellow-400 font-semibold transition-all flex flex-col items-start gap-0.5"
      >
        <span class="text-xs">diagnostic_only</span>
        <span class="text-[9px] text-yellow-600 font-normal">Ok: non-applied</span>
      </button>

      <button
        id="mock-scenario-partial"
        on:click={() => triggerMockDispatch('partial')}
        disabled={isDispatching}
        class="px-3 py-2 bg-yellow-950/30 border border-yellow-900/50 hover:bg-yellow-950/50 disabled:bg-gray-900 disabled:border-gray-800 rounded text-yellow-400 font-semibold transition-all flex flex-col items-start gap-0.5"
      >
        <span class="text-xs">partial</span>
        <span class="text-[9px] text-yellow-600 font-normal">Ok: non-applied</span>
      </button>

      <!-- ERR: Ingress Rejected -->
      <button
        id="mock-scenario-ingress-rejected"
        on:click={() => triggerMockDispatch('ingress_rejected')}
        disabled={isDispatching}
        class="px-3 py-2 bg-rose-950/30 border border-rose-900/50 hover:bg-rose-950/50 disabled:bg-gray-900 disabled:border-gray-800 rounded text-rose-400 font-semibold transition-all flex flex-col items-start gap-0.5"
      >
        <span class="text-xs">ingress_rejected</span>
        <span class="text-[9px] text-rose-600 font-normal">Err: ingress rejected</span>
      </button>

      <button
        id="mock-scenario-unknown-status"
        on:click={() => triggerMockDispatch('unknown_status')}
        disabled={isDispatching}
        class="px-3 py-2 bg-rose-950/30 border border-rose-900/50 hover:bg-rose-950/50 disabled:bg-gray-900 disabled:border-gray-800 rounded text-rose-400 font-semibold transition-all flex flex-col items-start gap-0.5"
      >
        <span class="text-xs">unknown status</span>
        <span class="text-[9px] text-rose-600 font-normal">Err: ingress rejected</span>
      </button>

      <button
        id="mock-scenario-invalid-sig"
        on:click={() => triggerMockDispatch('invalid_signature')}
        disabled={isDispatching}
        class="px-3 py-2 bg-rose-950/30 border border-rose-900/50 hover:bg-rose-950/50 disabled:bg-gray-900 disabled:border-gray-800 rounded text-rose-400 font-semibold transition-all flex flex-col items-start gap-0.5"
      >
        <span class="text-xs">invalid signature</span>
        <span class="text-[9px] text-rose-600 font-normal">Err: ingress rejected</span>
      </button>
    </div>
  </div>

  <!-- Outcome / Status Display Panel -->
  {#if commandOutcome !== null}
    <div class="border border-gray-900 bg-gray-950/50 rounded-lg p-3 space-y-2.5">
      <div class="flex items-center justify-between">
        <span class="text-gray-500 text-[10px] uppercase font-bold">Dispatch Outcome</span>
        <span class="px-2 py-0.5 rounded text-[10px] font-bold font-mono uppercase tracking-wider
          {commandOutcome === 'Ok' ? 'bg-emerald-950 text-emerald-400 border border-emerald-800' : 'bg-rose-950 text-rose-400 border border-rose-800'}"
        >
          Command outcome: {commandOutcome}
        </span>
      </div>

      <div class="grid grid-cols-2 gap-2 text-[11px]">
        <div>
          <span class="text-gray-500">Triggered Scenario:</span>
          <span class="text-gray-300 ml-1 font-bold">{lastScenario}</span>
        </div>
        <div>
          <span class="text-gray-500">Classification:</span>
          <span class="ml-1 font-bold
            {outcomeClassification.includes('applied)') ? 'text-emerald-400' : ''}
            {outcomeClassification.includes('non-applied)') ? 'text-yellow-400' : ''}
            {outcomeClassification.includes('rejected)') ? 'text-rose-400' : ''}"
          >
            {outcomeClassification}
          </span>
        </div>
      </div>

      <!-- Redaction Policy notice -->
      <div class="bg-gray-900/50 border border-gray-900 rounded p-2 text-[10px] text-gray-500 leading-normal">
        <span class="text-gray-400 font-bold">🔒 Redacted Trace Enforcement:</span>
        Raw outputs, diagnostic messages, slot values, and absolute paths are completely hidden. Only digests, keys, status vocabulary, and timestamps are registered.
      </div>

      {#if commandOutcome === 'Err'}
        <div class="bg-rose-950/20 border border-rose-950 rounded p-2.5 space-y-1">
          <div class="text-rose-400 text-[10px] uppercase font-bold">Ingress Error (Fail-Closed)</div>
          <div class="text-rose-300 text-xs break-all leading-normal">{lastErrorMessage}</div>
        </div>
      {:else if receivedReceipt}
        <div class="space-y-1.5">
          <div class="text-gray-500 text-[10px] uppercase font-bold">Generated Receipt Stub</div>
          <div class="bg-gray-900/40 border border-gray-900 rounded p-2 text-[10px] text-gray-400 space-y-1">
            <div class="truncate"><span class="text-gray-600">Trace ID:</span> {receivedReceipt.trace_id}</div>
            <div class="truncate"><span class="text-gray-600">Contract ID:</span> {receivedReceipt.contract_id}</div>
            <div class="truncate"><span class="text-gray-600">Event Type:</span> {receivedReceipt.event_type}</div>
            <div class="truncate"><span class="text-gray-600">Redaction Policy:</span> {receivedReceipt.redaction_policy}</div>
          </div>
        </div>
      {/if}
    </div>
  {/if}
</div>
