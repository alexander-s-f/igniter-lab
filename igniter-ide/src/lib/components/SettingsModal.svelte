<script lang="ts">
  import { createEventDispatcher } from 'svelte'
  import SettingsPanel from './SettingsPanel.svelte'

  export let open = false

  const dispatch = createEventDispatcher<{ close: void }>()

  function close() { open = false; dispatch('close') }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape') close()
  }
</script>

{#if open}
  <!-- svelte-ignore a11y_interactive_supports_focus -->
  <div
    class="fixed inset-0 z-50 flex items-start justify-center pt-12 pb-8 bg-black/60 backdrop-blur-sm overflow-y-auto"
    on:click={close}
    on:keydown={onKey}
    role="dialog" aria-modal="true" aria-label="Settings"
  >
    <div
      class="w-[680px] bg-gray-950 border border-gray-800 rounded-2xl shadow-2xl overflow-hidden flex flex-col mx-4"
      style="max-height: calc(100vh - 80px)"
      on:click|stopPropagation={() => {}}
      on:keydown|stopPropagation={onKey}
      role="presentation"
    >
      <!-- Header -->
      <div class="flex items-center justify-between px-6 py-4 border-b border-gray-800 shrink-0 bg-gray-900">
        <div class="flex items-center gap-3">
          <span class="text-gray-400 text-lg">���</span>
          <h2 class="text-sm font-bold text-white tracking-wide">Settings</h2>
        </div>
        <div class="flex items-center gap-3">
          <kbd class="text-[10px] text-gray-600 bg-gray-800 border border-gray-700 px-1.5 py-0.5 rounded">���,</kbd>
          <button on:click={close}
            class="w-7 h-7 flex items-center justify-center rounded-lg text-gray-500 hover:text-gray-300
                   hover:bg-gray-800 transition-colors">���</button>
        </div>
      </div>

      <!-- Scrollable content -->
      <div class="flex-1 overflow-y-auto px-6 py-5">
        <SettingsPanel />
      </div>
    </div>
  </div>
{/if}
