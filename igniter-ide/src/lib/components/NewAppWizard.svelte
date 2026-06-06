<script lang="ts">
  import { createEventDispatcher } from 'svelte'
  import { api } from '$lib/api'
  import type { AppConfig } from '$lib/types'

  export let open = false
  export let workspaceDir = ''

  const dispatch = createEventDispatcher<{ created: AppConfig; close: void }>()

  // ������ State ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let step = 1
  let creating = false
  let error = ''

  // Step 1: basic info
  let name = ''
  let description = ''

  // Step 2: architecture
  let topology = 'single'
  let instances = 2
  let backend = 'in_memory'

  // ������ Config data ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  const TOPOLOGIES = [
    { id: 'single', icon: '���', label: 'Single',  color: '#6b7280', desc: 'One instance ��� simple scripts, batch jobs' },
    { id: 'ring',   icon: '���', label: 'Ring',    color: '#06b6d4', desc: 'N instances in a ring ��� streaming pipelines' },
    { id: 'star',   icon: '���', label: 'Star',    color: '#eab308', desc: 'Hub + spokes ��� coordinator pattern' },
    { id: 'mesh',   icon: '���', label: 'Mesh',    color: '#a855f7', desc: 'Fully connected ��� agent swarm' },
  ]

  const BACKENDS = [
    { id: 'in_memory', icon: '���', label: 'In-Memory', desc: 'Fast, ephemeral ��� dev and testing' },
    { id: 'rocksdb',   icon: '����', label: 'RocksDB',   desc: 'Persistent local store' },
    { id: 'remote_tcp',icon: '����', label: 'Remote TCP', desc: 'Connect to igniter-store server' },
  ]

  // ������ Validation ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  $: nameValid   = /^[a-z][a-z0-9-]*$/.test(name)
  $: step1Valid  = name.length > 0 && nameValid
  $: step2Valid  = true
  $: canNext     = step === 1 ? step1Valid : step2Valid

  // ������ Actions ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  function next()  { if (step < 3 && canNext) step++ }
  function back()  { if (step > 1) step-- }

  function closeModal() {
    open = false; step = 1; name = ''; description = ''; error = ''
    topology = 'single'; instances = 2; backend = 'in_memory'
    dispatch('close')
  }

  async function create() {
    if (!workspaceDir || !nameValid) return
    creating = true; error = ''
    try {
      const appsDir = workspaceDir + '/apps'
      const config  = await api.createApp(appsDir, name, description)
      dispatch('created', config)
      closeModal()
    } catch (e) { error = String(e) }
    finally     { creating = false }
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape') closeModal()
    if (e.key === 'Enter' && step < 3 && canNext) next()
    if (e.key === 'Enter' && step === 3) create()
  }

  $: selectedTopology = TOPOLOGIES.find(t => t.id === topology)
  $: selectedBackend  = BACKENDS.find(b => b.id === backend)
</script>

{#if open}
  <!-- svelte-ignore a11y_interactive_supports_focus -->
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm"
    on:click={closeModal}
    on:keydown={onKey}
    role="dialog" aria-modal="true"
  >
    <div
      class="w-[520px] bg-gray-900 border border-gray-700 rounded-2xl shadow-2xl overflow-hidden flex flex-col"
      style="max-height: 90vh"
      on:click|stopPropagation={() => {}}
      on:keydown|stopPropagation={onKey}
      role="presentation"
    >
      <!-- Header -->
      <div class="px-5 py-4 border-b border-gray-800 flex items-center justify-between shrink-0">
        <div>
          <h2 class="text-sm font-bold text-white">New App</h2>
          <p class="text-xs text-gray-500 mt-0.5">
            {step === 1 ? 'Basic information' : step === 2 ? 'Architecture' : 'Review & create'}
          </p>
        </div>
        <button on:click={closeModal}
          class="w-7 h-7 flex items-center justify-center rounded-lg text-gray-500 hover:text-gray-300
                 hover:bg-gray-800 transition-colors text-sm">���</button>
      </div>

      <!-- Step indicator -->
      <div class="flex items-center gap-0 px-5 py-3 border-b border-gray-800 shrink-0">
        {#each [1,2,3] as s}
          <div class="flex items-center gap-0">
            <div class="flex items-center justify-center w-6 h-6 rounded-full text-[11px] font-bold transition-colors
                        {step >= s ? 'bg-blue-600 text-white' : 'bg-gray-800 text-gray-500'}">
              {#if step > s}���{:else}{s}{/if}
            </div>
            {#if s < 3}
              <div class="w-12 h-px mx-1 {step > s ? 'bg-blue-600' : 'bg-gray-800'}"></div>
            {/if}
          </div>
        {/each}
        <div class="ml-auto text-xs text-gray-600">Step {step} of 3</div>
      </div>

      <!-- Content -->
      <div class="flex-1 overflow-y-auto p-5">

        <!-- ������ Step 1: Basic info ������ -->
        {#if step === 1}
          <div class="space-y-4">
            <div>
              <label class="block text-xs text-gray-400 mb-1.5 font-medium">
                App name <span class="text-red-400">*</span>
              </label>
              <input
                bind:value={name}
                placeholder="my-app"
                spellcheck="false"
                class="w-full bg-gray-800 border rounded px-3 py-2 text-sm font-mono outline-none transition-colors
                       {name && !nameValid
                         ? 'border-red-600 focus:border-red-500'
                         : 'border-gray-700 focus:border-blue-500'}"
              />
              {#if name && !nameValid}
                <p class="text-xs text-red-400 mt-1">Lowercase letters, digits, hyphens only. Must start with a letter.</p>
              {:else if nameValid}
                <p class="text-xs text-gray-600 mt-1 font-mono">Will be created at: apps/{name}/</p>
              {:else}
                <p class="text-xs text-gray-600 mt-1">kebab-case, e.g. order-pipeline</p>
              {/if}
            </div>

            <div>
              <label class="block text-xs text-gray-400 mb-1.5 font-medium">Description <span class="text-gray-600">(optional)</span></label>
              <input
                bind:value={description}
                placeholder="What does this app do?"
                class="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-sm outline-none focus:border-blue-500"
              />
            </div>
          </div>

        <!-- ������ Step 2: Architecture ������ -->
        {:else if step === 2}
          <div class="space-y-5">
            <!-- Topology -->
            <div>
              <p class="text-xs text-gray-400 font-medium mb-2">Topology</p>
              <div class="grid grid-cols-2 gap-2">
                {#each TOPOLOGIES as t}
                  <button
                    on:click={() => topology = t.id}
                    class="flex items-start gap-2.5 p-3 rounded-lg border text-left transition-all
                           {topology === t.id
                             ? 'border-blue-600 bg-blue-950/40 ring-1 ring-blue-600/30'
                             : 'border-gray-700 bg-gray-800/50 hover:border-gray-600'}">
                    <span class="text-lg mt-0.5" style="color:{t.color}">{t.icon}</span>
                    <div>
                      <div class="text-xs font-semibold text-white">{t.label}</div>
                      <div class="text-[11px] text-gray-500 mt-0.5 leading-snug">{t.desc}</div>
                    </div>
                  </button>
                {/each}
              </div>

              {#if topology !== 'single'}
                <div class="mt-3 flex items-center gap-3">
                  <label class="text-xs text-gray-400 font-medium w-20">Instances</label>
                  <div class="flex items-center gap-2">
                    <button on:click={() => instances = Math.max(2, instances - 1)}
                      class="w-6 h-6 bg-gray-800 hover:bg-gray-700 rounded text-gray-300 transition-colors text-sm">���</button>
                    <span class="w-8 text-center text-sm font-mono text-white">{instances}</span>
                    <button on:click={() => instances = Math.min(16, instances + 1)}
                      class="w-6 h-6 bg-gray-800 hover:bg-gray-700 rounded text-gray-300 transition-colors text-sm">+</button>
                  </div>
                </div>
              {/if}
            </div>

            <!-- Backend -->
            <div>
              <p class="text-xs text-gray-400 font-medium mb-2">Storage backend</p>
              <div class="space-y-1.5">
                {#each BACKENDS as b}
                  <button
                    on:click={() => backend = b.id}
                    class="w-full flex items-center gap-3 p-2.5 rounded-lg border text-left transition-all
                           {backend === b.id
                             ? 'border-blue-600 bg-blue-950/30 ring-1 ring-blue-600/20'
                             : 'border-gray-700 bg-gray-800/40 hover:border-gray-600'}">
                    <span class="text-base w-5 text-center">{b.icon}</span>
                    <div class="flex-1 min-w-0">
                      <span class="text-xs font-semibold text-white">{b.label}</span>
                      <span class="text-xs text-gray-500 ml-2">{b.desc}</span>
                    </div>
                    {#if backend === b.id}
                      <span class="text-blue-400 text-xs">���</span>
                    {/if}
                  </button>
                {/each}
              </div>
            </div>
          </div>

        <!-- ������ Step 3: Review ������ -->
        {:else if step === 3}
          <div class="space-y-3">
            <div class="bg-gray-800/60 border border-gray-700 rounded-xl p-4 space-y-3">
              <div class="flex items-baseline gap-3">
                <span class="text-xs text-gray-500 w-20">Name</span>
                <span class="text-sm font-mono text-white font-semibold">{name}</span>
              </div>
              {#if description}
                <div class="flex items-baseline gap-3">
                  <span class="text-xs text-gray-500 w-20">Description</span>
                  <span class="text-sm text-gray-300">{description}</span>
                </div>
              {/if}
              <div class="flex items-center gap-3">
                <span class="text-xs text-gray-500 w-20">Topology</span>
                <span style="color:{selectedTopology?.color}" class="text-sm font-semibold">
                  {selectedTopology?.icon} {selectedTopology?.label}
                </span>
                {#if topology !== 'single'}
                  <span class="text-xs text-cyan-400">�� {instances} instances</span>
                {/if}
              </div>
              <div class="flex items-center gap-3">
                <span class="text-xs text-gray-500 w-20">Backend</span>
                <span class="text-sm text-gray-300">{selectedBackend?.icon} {selectedBackend?.label}</span>
              </div>
              <div class="flex items-baseline gap-3">
                <span class="text-xs text-gray-500 w-20">Location</span>
                <span class="text-xs font-mono text-gray-500">apps/{name}/</span>
              </div>
            </div>

            <div class="bg-blue-950/30 border border-blue-900/50 rounded-lg p-3 text-xs text-blue-300/80 leading-relaxed">
              A starter contract <code class="bg-blue-900/40 px-1 rounded">hello_world.ig</code> will be added
              to <code class="bg-blue-900/40 px-1 rounded">contracts/</code>.
            </div>

            {#if error}
              <div class="bg-red-950 border border-red-800 rounded-lg p-3 text-red-300 text-xs">
                ��� {error}
              </div>
            {/if}
          </div>
        {/if}

      </div>

      <!-- Footer -->
      <div class="px-5 py-4 border-t border-gray-800 flex items-center gap-2 flex-shrink-0">
        <button on:click={closeModal}
          class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 rounded-lg text-xs text-gray-300 transition-colors">
          Cancel
        </button>
        <div class="flex-1"></div>
        {#if step > 1}
          <button on:click={back}
            class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 rounded-lg text-xs text-gray-300 transition-colors">
            ��� Back
          </button>
        {/if}
        {#if step < 3}
          <button on:click={next} disabled={!canNext}
            class="px-4 py-1.5 bg-blue-600 hover:bg-blue-500 disabled:bg-gray-700 disabled:text-gray-500
                   rounded-lg text-xs font-semibold text-white transition-colors">
            Next ���
          </button>
        {:else}
          <button on:click={create} disabled={creating}
            class="px-4 py-1.5 bg-green-700 hover:bg-green-600 disabled:bg-gray-700
                   rounded-lg text-xs font-semibold text-white transition-colors flex items-center gap-1.5">
            {#if creating}
              <span class="animate-spin">���</span> Creating���
            {:else}
              ��� Create App
            {/if}
          </button>
        {/if}
      </div>
    </div>
  </div>
{/if}
