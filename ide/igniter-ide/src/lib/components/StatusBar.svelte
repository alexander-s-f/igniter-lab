<script lang="ts">
  import type { StatusInfo } from '$lib/types'
  import IgMark from './IgMark.svelte'
  export let status: StatusInfo
</script>

<header
  class="flex items-center justify-between px-4 py-1 bg-ink-2 border-b border-ink-line text-warm text-xs select-none"
>
  <div class="flex items-center gap-3">
    <IgMark variant="oval" class="w-4 h-4" />
    <span class="font-bold text-warm-3">Igniter IDE</span>
    <span class="opacity-60 font-sans">v0.1.0</span>
  </div>
  <div class="flex items-center gap-4">
    <span>backend: <span class="text-ember">{status.backend}</span></span>
    <span>facts: <span class="text-ember">{status.facts_count}</span></span>
    <span>contracts: <span class="text-ember">{status.contracts_count}</span></span>
    <span>obs: <span class="text-ember">{status.observations_count}</span></span>
  </div>
</header>
