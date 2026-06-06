<script lang="ts">
  import { createEventDispatcher, tick } from 'svelte'
  import type { ContractInfo } from '$lib/types'

  export let open = false
  export let contracts: ContractInfo[] = []

  const dispatch = createEventDispatcher<{
    close:       void
    openInDag:   string
    openDispatch:string
    command:     { id: string }
  }>()

  let query = ''
  let selectedIdx = 0
  let inputEl: HTMLInputElement

  interface Item {
    kind:   'contract' | 'cmd'
    icon:   string
    label:  string
    hint:   string
    action: () => void
  }

  const CMDS: Item[] = [
    { kind:'cmd', icon:'���', label:'DAG view',          hint:'View', action:() => emit('view.dag')      },
    { kind:'cmd', icon:'���', label:'Execution Tracer',  hint:'View', action:() => emit('view.tracer')   },
    { kind:'cmd', icon:'���', label:'Dispatch',           hint:'View', action:() => emit('view.dispatch') },
    { kind:'cmd', icon:'���', label:'System Graph',       hint:'View', action:() => emit('view.system')   },
    { kind:'cmd', icon:'���', label:'Temporal Timeline',  hint:'View', action:() => emit('view.timeline') },
  ]

  function emit(id: string) { dispatch('command', { id }); close() }
  function close()          { open = false; query = ''; dispatch('close') }

  let contractItems: Item[] = []
  $: contractItems = contracts.map(c => ({
    kind:   'contract' as const,
    icon:   '���',
    label:  c.name,
    hint:   `[${c.fragment_class}]`,
    action: () => { dispatch('openDispatch', c.name); close() },
  }))

  let all: Item[] = []
  $: all = [...contractItems, ...CMDS]

  $: filtered = query.trim()
    ? all.filter(i =>
        i.label.toLowerCase().includes(query.toLowerCase()) ||
        i.hint.toLowerCase().includes(query.toLowerCase()))
    : all

  $: selectedIdx = Math.min(selectedIdx, Math.max(0, filtered.length - 1))

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape')    { close(); return }
    if (e.key === 'ArrowDown') { e.preventDefault(); selectedIdx = (selectedIdx + 1) % (filtered.length || 1) }
    if (e.key === 'ArrowUp')   { e.preventDefault(); selectedIdx = (selectedIdx - 1 + (filtered.length || 1)) % (filtered.length || 1) }
    if (e.key === 'Enter' && filtered[selectedIdx]) { e.preventDefault(); filtered[selectedIdx].action() }
  }

  function onQueryInput() { selectedIdx = 0 }

  $: if (open) tick().then(() => { inputEl?.focus(); inputEl?.select() })
</script>

{#if open}
  <!-- svelte-ignore a11y_interactive_supports_focus -->
  <div
    class="fixed inset-0 z-50 flex items-start justify-center pt-20 bg-black/50 backdrop-blur-sm"
    on:click={close}
    on:keydown={onKey}
    role="dialog"
    aria-modal="true"
  >
    <div
      class="w-[580px] bg-gray-900 border border-gray-700 rounded-xl shadow-2xl overflow-hidden"
      on:click|stopPropagation={() => {}}
      on:keydown={onKey}
      role="presentation"
    >
      <!-- Search input -->
      <div class="flex items-center gap-3 px-4 py-3 border-b border-gray-800">
        <span class="text-gray-500 text-sm">���</span>
        <input
          bind:this={inputEl}
          bind:value={query}
          on:input={onQueryInput}
          on:keydown={onKey}
          placeholder="Contracts, views, commands���"
          class="flex-1 bg-transparent outline-none text-sm text-white placeholder-gray-600"
          spellcheck="false"
          autocomplete="off"
        />
        {#if query}
          <button on:click={() => { query = ''; selectedIdx = 0; inputEl?.focus() }}
            class="text-gray-600 hover:text-gray-400 transition-colors text-xs">���</button>
        {:else}
          <kbd class="text-[10px] text-gray-600 bg-gray-800 px-1.5 py-0.5 rounded border border-gray-700">Esc</kbd>
        {/if}
      </div>

      <!-- Results -->
      <div class="max-h-72 overflow-y-auto">
        {#if filtered.length === 0}
          <div class="px-4 py-5 text-gray-600 text-sm text-center">No results for "{query}"</div>
        {:else}
          {#each filtered as item, i}
            <button
              class="w-full flex items-center gap-3 px-4 py-2.5 text-left transition-colors
                     {i === selectedIdx ? 'bg-blue-600/25 text-white' : 'text-gray-300 hover:bg-gray-800'}"
              on:click={item.action}
              on:mouseenter={() => selectedIdx = i}
            >
              <span class="w-5 text-center shrink-0
                           {item.kind === 'contract' ? 'text-blue-400' : 'text-purple-400'} text-sm">
                {item.icon}
              </span>
              <span class="flex-1 min-w-0 text-sm truncate">{item.label}</span>
              <span class="text-xs text-gray-600 shrink-0 font-mono">{item.hint}</span>
            </button>
          {/each}
        {/if}
      </div>

      <!-- Footer -->
      <div class="px-4 py-2 border-t border-gray-800 flex items-center gap-4 text-[10px] text-gray-600">
        <span><kbd class="bg-gray-800 border border-gray-700 px-1 rounded">������</kbd> navigate</span>
        <span><kbd class="bg-gray-800 border border-gray-700 px-1 rounded">���</kbd> select</span>
        <span><kbd class="bg-gray-800 border border-gray-700 px-1 rounded">Esc</kbd> close</span>
        <span class="ml-auto">{filtered.length} results</span>
      </div>
    </div>
  </div>
{/if}
