<script lang="ts">
  import { createEventDispatcher } from 'svelte'
  import { buildsStore, runsStore } from '$lib/stores/artifacts'
  import type { RunRecord } from '$lib/stores/artifacts'

  let tab: 'builds' | 'runs' = 'builds'

  $: builds = $buildsStore
  $: runs   = $runsStore

  const dispatch = createEventDispatcher<{ replay: RunRecord; openArtifact: string }>()

  function fmt(ts: number) {
    return new Date(ts).toLocaleTimeString([], { hour:'2-digit', minute:'2-digit', second:'2-digit' })
  }

  function dur(ms: number) {
    return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(2)}s`
  }

  function truncate(s: string, n = 60) {
    return s.length > n ? s.slice(0, n) + '���' : s
  }

  function artifactName(path: string) {
    return path.split('/').pop() ?? path
  }
</script>

<div class="flex flex-col h-full text-xs font-mono overflow-hidden">

  <!-- Sub-tabs -->
  <div class="flex items-center border-b border-ink-line shrink-0 bg-ink-1">
    <button
      on:click={() => tab = 'builds'}
      class="px-3 py-1.5 transition-colors whitespace-nowrap cursor-pointer
             {tab === 'builds' ? 'text-ignite border-b border-ignite font-semibold' : 'text-warm/50 hover:text-warm-3'}">
      Builds
      <span class="ml-1 text-warm/30">({builds.length})</span>
    </button>
    <button
      on:click={() => tab = 'runs'}
      class="px-3 py-1.5 transition-colors whitespace-nowrap cursor-pointer
             {tab === 'runs' ? 'text-ignite border-b border-ignite font-semibold' : 'text-warm/50 hover:text-warm-3'}">
      Runs
      <span class="ml-1 text-warm/30">({runs.length})</span>
    </button>
  </div>

  <!-- Content -->
  <div class="flex-1 overflow-y-auto">

    {#if tab === 'builds'}
      {#if builds.length === 0}
        <div class="p-4 text-warm/40 text-center leading-relaxed">
          No builds yet.<br/>
          <span class="text-warm/30">Compile a contract to see history.</span>
        </div>
      {:else}
        {#each builds as b (b.id)}
          <div class="flex items-start gap-2 px-3 py-2 border-b border-ink-line/40
                      hover:bg-ink-2 transition-colors group">
            <span class="shrink-0 mt-0.5 {b.success ? 'text-core' : 'text-oof'}">
              {b.success ? '���' : '���'}
            </span>
            <div class="flex-1 min-w-0">
              <div class="font-mono text-warm-3 truncate font-medium">{b.contractName}
                {#if b.sourceLength}
                  <span class="text-warm/40 text-[10px] font-normal ml-1">{b.sourceLength}B</span>
                {/if}
              </div>
              <div class="text-warm/50 truncate mt-0.5">{truncate(b.message)}</div>
              {#if b.artifactPath}
                <div class="flex items-center gap-1.5 mt-0.5">
                  <span class="text-warm/40 text-[10px] font-mono truncate"
                        title={b.artifactPath}>
                    ���� {artifactName(b.artifactPath)}
                  </span>
                  <button
                    on:click={() => dispatch('openArtifact', b.artifactPath ?? '')}
                    class="opacity-0 group-hover:opacity-100 text-[10px] text-ignite
                           hover:text-ember transition-all shrink-0 cursor-pointer">
                    Open
                  </button>
                </div>
              {/if}
            </div>
            <span class="text-warm/40 shrink-0 tabular-nums">{fmt(b.ts)}</span>
          </div>
        {/each}
      {/if}

    {:else}
      {#if runs.length === 0}
        <div class="p-4 text-warm/40 text-center leading-relaxed">
          No runs yet.<br/>
          <span class="text-warm/30">Dispatch a contract to see history.</span>
        </div>
      {:else}
        {#each runs as r (r.id)}
          <div class="px-3 py-2 border-b border-ink-line/40 hover:bg-ink-2 transition-colors group">
            <div class="flex items-center gap-2">
              <span class="shrink-0 {r.error ? 'text-oof' : 'text-core'}">
                {r.error ? '���' : '���'}
              </span>
              <span class="font-mono text-warm-3 flex-1 truncate font-medium">{r.contractName}</span>
              <span class="text-escape font-semibold tabular-nums shrink-0">{dur(r.durationMs)}</span>
              <span class="text-warm/40 tabular-nums shrink-0">{fmt(r.ts)}</span>
              <button
                on:click={() => dispatch('replay', r)}
                class="shrink-0 opacity-0 group-hover:opacity-100 text-ignite
                       hover:text-ember transition-all px-1 rounded cursor-pointer"
                title="Replay with same inputs">
                ���
              </button>
            </div>

            {#if r.error}
              <div class="text-oof/80 mt-0.5 pl-4 leading-tight">
                {truncate(r.error, 80)}
              </div>
            {:else}
              <div class="text-warm/50 mt-0.5 pl-4 font-mono leading-tight">
                ��� {truncate(JSON.stringify(r.result))}
              </div>
            {/if}

            <!-- Inputs preview on hover -->
            {#if Object.keys(r.inputs ?? {}).length > 0}
              <div class="hidden group-hover:block text-warm/30 mt-0.5 pl-4 font-mono leading-tight">
                ��� {truncate(JSON.stringify(r.inputs), 60)}
              </div>
            {/if}
          </div>
        {/each}
      {/if}
    {/if}

  </div>
</div>
