<script lang="ts">
  import { createEventDispatcher } from 'svelte'
  import { api } from '$lib/api'
  import type { ContractInfo } from '$lib/types'
  import { artifacts } from '$lib/stores/artifacts'

  export let contracts: ContractInfo[] = []
  export let selected = ''
  export let initialInputs: string = ''

  const dispatch = createEventDispatcher()
  let inputs = '{}'
  let result: any = null
  let error = ''
  let loading = false

  function getRunErrorStage(err: string): string {
    const msg = err.toLowerCase()
    if (msg.includes('missing loop collection') || msg.includes('ast') || msg.includes('unsupported ast') || msg.includes('not found') || msg.includes('requires matching capability')) {
      return 'VM compile'
    }
    return 'VM run'
  }

  async function run() {
    if (!selected) { error = 'Select a contract first'; return }
    let parsed: Record<string, any> = {}
    try { parsed = JSON.parse(inputs) } catch { error = 'Invalid JSON inputs'; return }
    loading = true; error = ''; result = null
    const start = Date.now()
    try {
      result = await api.dispatch(selected, inputs)
      const durationMs = Date.now() - start
      artifacts.addRun({
        contractName: selected,
        ts:           Date.now(),
        inputs:       parsed,
        result,
        durationMs,
      })
      artifacts.addDebugEvent({
        type: 'run',
        timestamp: start,
        contractName: selected,
        success: true,
        durationMs,
        inputs: parsed,
        result
      })
      dispatch('refresh')
    } catch (e) {
      const msg = String(e)
      const durationMs = Date.now() - start
      artifacts.addRun({
        contractName: selected,
        ts:           Date.now(),
        inputs:       parsed,
        result:       null,
        durationMs,
        error:        msg,
      })
      artifacts.addDebugEvent({
        type: 'run',
        timestamp: start,
        contractName: selected,
        success: false,
        durationMs,
        inputs: parsed,
        error: msg,
        errorStage: getRunErrorStage(msg)
      })
      error = msg
    } finally {
      loading = false
    }
  }

  $: if (selected) {
    inputs = initialInputs || '{}'
    error = ''
    result = null
  }
</script>

<div class="max-w-3xl space-y-4">
  <div>
    <label class="block text-xs text-gray-400 mb-1">Contract</label>
    <select
      bind:value={selected}
      class="w-full bg-gray-900 border border-gray-700 rounded px-3 py-2 text-sm focus:border-blue-500 outline-none"
    >
      <option value="">��� select ���</option>
      {#each contracts as c}
        <option value={c.name}>{c.name} [{c.fragment_class}]</option>
      {/each}
    </select>
  </div>

  <div>
    <label class="block text-xs text-gray-400 mb-1">Inputs (JSON)</label>
    <textarea
      bind:value={inputs}
      rows="6"
      class="w-full bg-gray-900 border border-gray-700 rounded px-3 py-2 text-sm font-mono focus:border-blue-500 outline-none resize-y"
    ></textarea>
  </div>

  <button
    on:click={run}
    disabled={loading || !selected}
    class="px-4 py-2 bg-blue-600 hover:bg-blue-500 disabled:bg-gray-700 disabled:text-gray-500 rounded text-sm font-semibold transition-colors"
  >
    {loading ? 'Running���' : '��� Dispatch'}
  </button>

  {#if error}
    <div class="bg-red-950 border border-red-800 rounded p-3 text-red-300 text-sm">
      ��� {error}
    </div>
  {/if}

  {#if result !== null}
    <div class="bg-gray-900 border border-gray-700 rounded">
      <div class="px-3 py-1 border-b border-gray-700 text-xs text-green-400">��� Result</div>
      <pre class="p-3 text-sm text-yellow-300 overflow-auto">{JSON.stringify(result, null, 2)}</pre>
    </div>
  {/if}
</div>
