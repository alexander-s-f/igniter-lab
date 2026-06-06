<script lang="ts">
  import type { ContractInfo } from '$lib/types'
  export let contracts: ContractInfo[] = []
  export let selected = ''

  const fragmentStyle = (cls: string): string =>
    ({
      core: 'text-green-400',
      escape: 'text-yellow-400',
      temporal: 'text-cyan-400',
      oof: 'text-red-400',
    }[cls] ?? 'text-gray-400')
</script>

<div class="flex-1 overflow-auto py-1">
  {#if contracts.length === 0}
    <p class="text-gray-600 text-xs px-3 py-4 text-center">
      No contracts loaded.<br />Click + Load to open a .ig file.
    </p>
  {/if}
  {#each contracts as c}
    <button
      class="w-full text-left px-3 py-2 text-sm hover:bg-gray-800 transition-colors {selected ===
      c.name
        ? 'bg-gray-800 border-l-2 border-blue-500'
        : ''}"
      on:click={() => (selected = c.name)}
    >
      <div class="flex items-center gap-2">
        <span class={fragmentStyle(c.fragment_class)}>���</span>
        <span class="truncate">{c.name}</span>
      </div>
      <div class="text-xs text-gray-500 pl-4">[{c.fragment_class}]</div>
    </button>
  {/each}
</div>
