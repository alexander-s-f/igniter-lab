<script lang="ts">
  import { createEventDispatcher } from 'svelte'
  import type { AppConfig } from '$lib/types'
  import NewAppWizard from './NewAppWizard.svelte'

  export let workspaceDir: string = ''
  export let apps: AppConfig[] = []

  const dispatch = createEventDispatcher<{ appsChanged: AppConfig[] }>()

  let wizardOpen = false

  const TOPOLOGY_META: Record<string, { icon: string; color: string; label: string }> = {
    single: { icon: '���', color: '#6b7280', label: 'Single' },
    ring:   { icon: '���', color: '#06b6d4', label: 'Ring' },
    star:   { icon: '���', color: '#eab308', label: 'Star' },
    mesh:   { icon: '���', color: '#a855f7', label: 'Mesh' },
  }

  const BACKEND_ICON: Record<string, string> = {
    in_memory: '���', rocksdb: '����', remote_tcp: '����',
  }

  function handleCreated(app: AppConfig) {
    apps = [...apps, app]
    dispatch('appsChanged', apps)
  }
</script>

<!-- Wizard overlay (portal-like, rendered outside panel) -->
<NewAppWizard
  bind:open={wizardOpen}
  {workspaceDir}
  on:created={(e) => handleCreated(e.detail)}
/>

<div class="space-y-2">

  <!-- Header row -->
  <div class="flex items-center justify-between mb-3">
    <span class="text-xs text-gray-500">{apps.length} app{apps.length !== 1 ? 's' : ''}</span>
    <button
      on:click={() => wizardOpen = true}
      disabled={!workspaceDir}
      class="flex items-center gap-1.5 px-2.5 py-1 bg-blue-700 hover:bg-blue-600
             disabled:bg-gray-800 disabled:text-gray-600 rounded text-xs font-semibold transition-colors">
      <span>���</span> New App
    </button>
  </div>

  <!-- App list -->
  {#if apps.length === 0}
    <div class="text-center py-6 text-gray-600 text-xs">
      <div class="text-2xl mb-2 opacity-20">���</div>
      No apps yet.<br/>
      <button on:click={() => wizardOpen = true} disabled={!workspaceDir}
        class="text-blue-500 hover:text-blue-400 transition-colors mt-1 disabled:opacity-40">
        Create your first app ���
      </button>
    </div>
  {:else}
    {#each apps as app}
      {@const meta = TOPOLOGY_META[app.swarm.topology] ?? TOPOLOGY_META.single}
      <div class="bg-gray-900/60 border border-gray-800 rounded-xl p-3 text-xs hover:border-gray-700 transition-colors">
        <div class="flex items-start gap-2">
          <span style="color:{meta.color}" class="text-base mt-0.5 shrink-0">{meta.icon}</span>
          <div class="flex-1 min-w-0">
            <div class="flex items-baseline gap-2">
              <span class="font-semibold text-sm text-gray-200">{app.name}</span>
              <span class="text-gray-600">{app.version}</span>
            </div>
            {#if app.description}
              <div class="text-gray-500 mt-0.5 truncate">{app.description}</div>
            {/if}
            <div class="flex items-center gap-2 mt-1.5 flex-wrap">
              <span class="px-1.5 py-0.5 rounded text-[10px] font-semibold"
                    style="background:{meta.color}20; color:{meta.color}">
                {meta.label}
                {#if app.swarm.instances > 1}��{app.swarm.instances}{/if}
              </span>
              <span class="text-gray-600">
                {BACKEND_ICON[app.backend.backend_type] ?? ''} {app.backend.backend_type}
              </span>
            </div>
          </div>
        </div>
      </div>
    {/each}
  {/if}
</div>
