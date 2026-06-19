<script lang="ts">
  import { onMount } from 'svelte'
  import { api } from '$lib/api'
  import type { ObsInfo } from '$lib/types'

  let observations: ObsInfo[] = []
  let loading = false

  async function load() {
    loading = true
    try {
      observations = await api.listObservations()
    } catch (_) {
    } finally {
      loading = false
    }
  }

  async function clear() {
    await api.clearObservations()
    observations = []
  }

  onMount(() => {
    load()
    const t = setInterval(load, 2000)
    return () => clearInterval(t)
  })

  function ts(t: number): string {
    return new Date(t * 1000).toLocaleTimeString()
  }

  const kindColor = (k: string): string =>
    ({
      bid_summary: 'text-green-400',
      contract_done: 'text-blue-400',
      invariant_warn: 'text-yellow-400',
      invariant_error: 'text-red-400',
    }[k] ?? 'text-cyan-400')
</script>

<div class="max-w-4xl space-y-3">
  <div class="flex items-center justify-between">
    <span class="text-sm text-gray-400">{observations.length} observations</span>
    <button on:click={clear} class="text-xs text-gray-500 hover:text-red-400 transition-colors">
      Clear
    </button>
  </div>

  {#if observations.length === 0}
    <p class="text-gray-600 text-sm">
      No observations yet. Dispatch a contract to generate observations.
    </p>
  {/if}

  <div class="space-y-1">
    {#each [...observations].reverse() as obs}
      <div class="flex items-start gap-3 bg-gray-900 rounded px-3 py-2 text-sm">
        <span class="text-gray-500 text-xs w-20 shrink-0">{ts(obs.timestamp)}</span>
        <span class="{kindColor(obs.kind)} w-36 shrink-0 truncate">{obs.kind}</span>
        <pre class="text-xs text-yellow-300 flex-1 overflow-hidden text-ellipsis">{JSON.stringify(obs.value)}</pre>
      </div>
    {/each}
  </div>
</div>
