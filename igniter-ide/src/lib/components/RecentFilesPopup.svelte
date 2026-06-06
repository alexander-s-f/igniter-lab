<script lang="ts">
  import { createEventDispatcher } from 'svelte'

  export let open = false
  export let files: string[] = []

  const dispatch = createEventDispatcher<{
    select: string
    close: void
  }>()

  let query = ''
  let selectedIdx = 0

  $: filtered = query
    ? files.filter(f => f.toLowerCase().includes(query.toLowerCase()))
    : files

  $: if (open) { query = ''; selectedIdx = 0 }
  $: if (selectedIdx >= filtered.length) selectedIdx = Math.max(0, filtered.length - 1)

  function select(path: string) {
    dispatch('select', path)
    close()
  }

  function close() {
    dispatch('close')
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') { e.preventDefault(); close(); return }
    if (e.key === 'ArrowDown') { e.preventDefault(); selectedIdx = Math.min(selectedIdx + 1, filtered.length - 1) }
    if (e.key === 'ArrowUp')   { e.preventDefault(); selectedIdx = Math.max(selectedIdx - 1, 0) }
    if (e.key === 'Enter' && filtered[selectedIdx]) { e.preventDefault(); select(filtered[selectedIdx]) }
  }

  function shortPath(p: string): string {
    const parts = p.split('/')
    return parts.length > 3 ? '���/' + parts.slice(-2).join('/') : parts.slice(-2).join('/')
  }

  function dirPart(p: string): string {
    const parts = p.split('/')
    return parts.slice(-2, -1)[0] ?? ''
  }

  function fileName(p: string): string {
    return p.split('/').pop() ?? p
  }
</script>

{#if open}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="fixed inset-0 z-50 flex items-start justify-center pt-24 bg-black/60"
    on:keydown={onKeydown}
    on:click|self={close}
  >
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
      class="bg-gray-900 border border-gray-700 rounded-xl shadow-2xl w-[540px] max-h-96
             flex flex-col overflow-hidden"
      on:click|stopPropagation={() => {}}
    >
      <!-- Search input -->
      <div class="flex items-center gap-2.5 px-4 py-3 border-b border-gray-800">
        <span class="text-gray-600 text-sm">����</span>
        <!-- svelte-ignore a11y_autofocus -->
        <input
          autofocus
          bind:value={query}
          placeholder="Recent files���"
          class="flex-1 bg-transparent text-sm text-gray-100 outline-none placeholder-gray-600"
        />
        <span class="text-[10px] text-gray-700">���E</span>
      </div>

      <!-- File list -->
      <div class="flex-1 overflow-y-auto py-1">
        {#if filtered.length === 0}
          <div class="px-4 py-3 text-xs text-gray-600 italic">
            {files.length === 0 ? 'No recently opened files.' : 'No matches.'}
          </div>
        {:else}
          {#each filtered as path, i}
            <button
              on:click={() => select(path)}
              on:mouseenter={() => selectedIdx = i}
              class="w-full flex items-center gap-3 px-4 py-2 text-left transition-colors
                     {i === selectedIdx ? 'bg-blue-600/25' : 'hover:bg-gray-800/50'}"
            >
              <span class="text-blue-400/70 text-[10px] shrink-0">���</span>
              <div class="flex-1 min-w-0">
                <div class="text-xs text-gray-100 truncate font-mono">{fileName(path)}</div>
                <div class="text-[10px] text-gray-600 truncate mt-0.5">{shortPath(path)}</div>
              </div>
              {#if i === selectedIdx}
                <span class="text-[10px] text-gray-600 shrink-0">���</span>
              {/if}
            </button>
          {/each}
        {/if}
      </div>

      <div class="px-4 py-2 border-t border-gray-800 text-[10px] text-gray-700 flex gap-3">
        <span>������ navigate</span>
        <span>��� open</span>
        <span>Esc close</span>
      </div>
    </div>
  </div>
{/if}
