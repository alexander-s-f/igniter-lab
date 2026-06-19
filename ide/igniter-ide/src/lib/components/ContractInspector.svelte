<script lang="ts">
  import { createEventDispatcher } from 'svelte'
  import { api } from '$lib/api'

  export let contractName: string = ''

  const dispatch = createEventDispatcher<{
    openInDag:     string
    openDispatch:  string
  }>()

  let ir: any = null
  let loading = false
  let error = ''
  let expandedSection: 'inputs' | 'nodes' | 'outputs' | null = 'nodes'

  async function loadIr(name: string) {
    if (!name) { ir = null; return }
    loading = true; error = ''
    try   { ir = await api.getContractIr(name) }
    catch (e) { error = String(e) }
    finally   { loading = false }
  }

  $: loadIr(contractName)

  const FRAG_BADGE: Record<string, string> = {
    core:     'bg-core/10     text-core      border-core/30',
    escape:   'bg-escape/10   text-escape    border-escape/30',
    temporal: 'bg-temporal/10 text-temporal  border-temporal/30',
    oof:      'bg-oof/10      text-oof       border-oof/30',
  }

  const KIND_BADGE: Record<string, string> = {
    compute:      'bg-core/15      text-core',
    read:         'bg-escape/15    text-escape',
    loop:         'bg-ignite/15    text-ignite',
    service_loop: 'bg-temporal/15  text-temporal',
    invariant:    'bg-oof/15       text-oof',
    snapshot:     'bg-temporal/10  text-temporal',
    fold_stream:  'bg-amber/15     text-amber',
    window:       'bg-temporal/15  text-temporal',
  }

  $: inputs    = ir?.input_ports   ?? ir?.inputs  ?? []
  $: nodes     = ir?.compute_nodes ?? ir?.nodes   ?? []
  $: outputs   = ir?.output_ports  ?? ir?.outputs ?? []
  $: fragClass = ir?.fragment_class ?? ir?.modifier ?? 'unknown'
  $: fragBadge = FRAG_BADGE[fragClass] ?? 'bg-ink-2 text-warm border-ink-line'

  function toggle(sec: 'inputs' | 'nodes' | 'outputs') {
    expandedSection = expandedSection === sec ? null : sec
  }
</script>

<div class="flex flex-col h-full overflow-hidden text-xs font-mono">

  {#if !contractName}
    <div class="flex-1 flex items-center justify-center text-warm/40 p-4 text-center">
      <div>
        <div class="text-3xl mb-2 opacity-30">���</div>
        <div>Select a contract to inspect</div>
      </div>
    </div>

  {:else if loading}
    <div class="p-3 text-temporal flex items-center gap-2">
      <span class="animate-spin">���</span> Loading���
    </div>

  {:else if error}
    <div class="p-3 text-oof text-xs bg-oof/10 rounded border border-oof/20 m-2">{error}</div>

  {:else if ir}

    <!-- Header -->
    <div class="px-3 py-2.5 border-b border-ink-line shrink-0 bg-ink-1">
      <div class="font-bold text-sm text-warm-3 truncate" title={contractName}>{contractName}</div>
      <div class="mt-1.5 flex items-center gap-2 flex-wrap">
        <span class="px-1.5 py-0.5 rounded border text-[10px] font-semibold tracking-wide {fragBadge}">
          {fragClass}
        </span>
        <span class="text-warm/50 tabular-nums">
          {inputs.length}��� �� {nodes.length}��� �� {outputs.length}���
        </span>
      </div>
    </div>

    <!-- Quick actions -->
    <div class="px-2 py-1.5 flex gap-1.5 border-b border-ink-line bg-ink-1/30 shrink-0">
      <button
        on:click={() => dispatch('openInDag', contractName)}
        class="flex-1 px-2 py-1 bg-ignite/10 hover:bg-ignite/25 border border-ignite/20 rounded text-ignite transition-colors text-[11px] font-medium cursor-pointer">
        ��� DAG
      </button>
      <button
        on:click={() => dispatch('openDispatch', contractName)}
        class="flex-1 px-2 py-1 bg-core/10 hover:bg-core/25 border border-core/20 rounded text-core transition-colors text-[11px] font-medium cursor-pointer">
        ��� Dispatch
      </button>
    </div>

    <!-- Sections -->
    <div class="flex-1 overflow-y-auto">

      <!-- ������ Inputs ������ -->
      <div>
        <button
          on:click={() => toggle('inputs')}
          class="w-full flex items-center justify-between px-3 py-1.5 hover:bg-ink-2 transition-colors cursor-pointer">
          <span class="text-temporal font-semibold">
            Inputs <span class="text-warm/40 font-normal">({inputs.length})</span>
          </span>
          <span class="text-warm/40 text-[10px]">{expandedSection === 'inputs' ? '���' : '���'}</span>
        </button>
        {#if expandedSection === 'inputs'}
          <div class="pb-2 px-3 space-y-1">
            {#if inputs.length === 0}
              <div class="text-warm/40 italic pl-2">none</div>
            {/if}
            {#each inputs as inp}
              <div class="flex items-baseline gap-2 py-0.5 pl-2">
                <span class="text-warm-3 font-mono">{inp.name}</span>
                <span class="text-warm font-mono text-[11px]">{inp.type_tag ?? inp.type?.name ?? '?'}</span>
                {#if inp.required === false}
                  <span class="text-warm/30 text-[9px] uppercase tracking-wider font-sans">opt</span>
                {/if}
                {#if inp.lifecycle && inp.lifecycle !== 'local'}
                  <span class="text-temporal/70 text-[9px] font-sans">{inp.lifecycle}</span>
                {/if}
              </div>
            {/each}
          </div>
        {/if}
      </div>

      <!-- ������ Nodes ������ -->
      <div class="border-t border-ink-line/50">
        <button
          on:click={() => toggle('nodes')}
          class="w-full flex items-center justify-between px-3 py-1.5 hover:bg-ink-2 transition-colors cursor-pointer">
          <span class="text-core font-semibold">
            Nodes <span class="text-warm/40 font-normal">({nodes.length})</span>
          </span>
          <span class="text-warm/40 text-[10px]">{expandedSection === 'nodes' ? '���' : '���'}</span>
        </button>
        {#if expandedSection === 'nodes'}
          <div class="pb-2 px-3 space-y-2">
            {#if nodes.length === 0}
              <div class="text-warm/40 italic pl-2">none</div>
            {/if}
            {#each nodes as node}
              {@const kind  = node.kind ?? 'compute'}
              {@const badge = KIND_BADGE[kind] ?? 'bg-ink-2 text-warm'}
              {@const deps  = node.dependencies ?? node.deps ?? []}
              <div class="pl-2">
                <div class="flex items-center gap-1.5 flex-wrap">
                  <span class="px-1.5 py-0.5 rounded text-[9px] font-bold {badge}">{kind}</span>
                  <span class="text-warm-3 font-mono">{node.name}</span>
                  {#if node.type_tag}
                    <span class="text-warm font-mono text-[10px]">{node.type_tag}</span>
                  {/if}
                </div>
                {#if deps.length > 0}
                  <div class="text-warm/40 mt-0.5 text-[10px] leading-tight">
                    ��� {deps.join(' �� ')}
                  </div>
                {/if}
              </div>
            {/each}
          </div>
        {/if}
      </div>

      <!-- ������ Outputs ������ -->
      <div class="border-t border-ink-line/50">
        <button
          on:click={() => toggle('outputs')}
          class="w-full flex items-center justify-between px-3 py-1.5 hover:bg-ink-2 transition-colors cursor-pointer">
          <span class="text-ember font-semibold">
            Outputs <span class="text-warm/40 font-normal">({outputs.length})</span>
          </span>
          <span class="text-warm/40 text-[10px]">{expandedSection === 'outputs' ? '���' : '���'}</span>
        </button>
        {#if expandedSection === 'outputs'}
          <div class="pb-2 px-3 space-y-1">
            {#if outputs.length === 0}
              <div class="text-warm/40 italic pl-2">none</div>
            {/if}
            {#each outputs as out}
              <div class="flex items-baseline gap-2 py-0.5 pl-2">
                <span class="text-ember font-mono">{out.name}</span>
                <span class="text-warm font-mono text-[11px]">{out.type_tag ?? out.type?.name ?? '?'}</span>
              </div>
            {/each}
          </div>
        {/if}
      </div>

      <!-- ������ Raw IR ������ -->
      <div class="border-t border-ink-line/50 font-sans">
        <details class="group">
          <summary class="flex items-center justify-between px-3 py-1.5 cursor-pointer
                          hover:bg-ink-2 transition-colors list-none select-none font-mono">
            <span class="text-warm font-semibold">Raw IR</span>
            <span class="text-warm/40 text-[10px] group-open:hidden">���</span>
            <span class="text-warm/40 text-[10px] hidden group-open:inline">���</span>
          </summary>
          <div class="px-2 pb-3">
            <pre class="text-[10px] text-warm/70 bg-ink-1 border border-ink-line rounded p-2 overflow-auto max-h-52 leading-relaxed whitespace-pre-wrap font-mono">{JSON.stringify(ir, null, 2)}</pre>
          </div>
        </details>
      </div>

    </div>
  {/if}

</div>
