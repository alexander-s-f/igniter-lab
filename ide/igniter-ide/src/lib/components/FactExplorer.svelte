<script lang="ts">
  import { api } from '$lib/api'
  import type { FactInfo } from '$lib/types'

  let store = ''
  let key = ''
  let asOf = ''
  let facts: FactInfo[] = []
  let loading = false
  let error = ''

  async function query() {
    if (!store) {
      error = 'Store is required'
      return
    }
    loading = true
    error = ''
    try {
      facts = await api.readFacts(store, key || 'global', asOf ? parseFloat(asOf) : undefined)
    } catch (e) {
      error = String(e)
    } finally {
      loading = false
    }
  }

  function ts(t: number): string {
    return new Date(t * 1000).toLocaleString()
  }
</script>

<div class="max-w-4xl space-y-4">
  <div class="flex gap-2">
    <input
      bind:value={store}
      placeholder="store (e.g. leads)"
      class="flex-1 bg-gray-900 border border-gray-700 rounded px-3 py-2 text-sm outline-none focus:border-blue-500"
    />
    <input
      bind:value={key}
      placeholder="key (optional)"
      class="flex-1 bg-gray-900 border border-gray-700 rounded px-3 py-2 text-sm outline-none focus:border-blue-500"
    />
    <input
      bind:value={asOf}
      placeholder="as_of (unix ts)"
      class="w-40 bg-gray-900 border border-gray-700 rounded px-3 py-2 text-sm outline-none focus:border-blue-500"
    />
    <button
      on:click={query}
      disabled={loading}
      class="px-4 py-2 bg-blue-600 hover:bg-blue-500 disabled:bg-gray-700 rounded text-sm font-semibold transition-colors"
    >
      Query
    </button>
  </div>

  {#if error}
    <div class="text-red-400 text-sm">��� {error}</div>
  {/if}

  {#if facts.length > 0}
    <div class="space-y-2">
      {#each facts as f}
        <div class="bg-gray-900 border border-gray-800 rounded p-3">
          <div class="flex items-center gap-3 text-xs text-gray-400 mb-2">
            <span class="text-blue-400 font-mono truncate">{f.id.slice(0, 8)}���</span>
            <span>tx: {ts(f.transaction_time)}</span>
            {#if f.valid_time}
              <span class="text-cyan-400">valid: {ts(f.valid_time)}</span>
            {/if}
            {#if f.causation}
              <span class="text-gray-500">��� {f.causation.slice(0, 8)}</span>
            {/if}
          </div>
          <pre class="text-yellow-300 text-xs overflow-auto">{JSON.stringify(f.value, null, 2)}</pre>
        </div>
      {/each}
    </div>
  {:else if !loading}
    <p class="text-gray-600 text-sm">No facts found. Try querying a store.</p>
  {/if}
</div>
