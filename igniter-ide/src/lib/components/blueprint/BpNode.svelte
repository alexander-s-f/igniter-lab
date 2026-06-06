<!--
  BpNode.svelte ��� Renders a single node card.
  Extensibility: add new kind entry in NODE_KIND_META to customise look.
  Draggable: emits 'dragmove' and 'dragend'.
  Port clicks: emits 'portdown' / 'portup' for edge creation.
-->
<script lang="ts">
  import { createEventDispatcher } from 'svelte'
  import type { BpNode, Port } from '$lib/blueprint/ir'

  export let node: BpNode
  export let selected = false
  export let dimmed   = false
  export let inputValue = ''
  export let evaluatedValue = ''
  export let error = ''

  const dispatch = createEventDispatcher<{
    select:   string                                    // nodeId
    dragmove: { id: string; dx: number; dy: number }
    dragend:  { id: string }
    portdown: { nodeId: string; portId: string; x: number; y: number; kind: 'in'|'out' }
    portup:   { nodeId: string; portId: string }
    gotosource: number                                  // line number
    inputValueChange: { name: string; value: string }
  }>()

  // ������ Kind meta (lego: add new kinds here) ������������������������������������������������������������������������������������������������������

  interface KindMeta {
    label:      string
    accent:     string    // Tailwind border colour class
    headerBg:   string    // Tailwind header bg class
    icon:       string
    iconColor:  string
  }

  const NODE_KIND_META: Record<string, KindMeta> = {
    input:    { label: 'INPUT',    accent: 'border-core/50',     headerBg: 'bg-core/10',     icon: '���',  iconColor: 'text-core'  },
    compute:  { label: 'COMPUTE',  accent: 'border-core/50',     headerBg: 'bg-core/10',     icon: '=',  iconColor: 'text-core'  },
    output:   { label: 'OUTPUT',   accent: 'border-ember/50',    headerBg: 'bg-ember/10',    icon: '���',  iconColor: 'text-ember' },
    read:     { label: 'READ',     accent: 'border-escape/50',   headerBg: 'bg-escape/10',   icon: '���', iconColor: 'text-escape' },
    snapshot: { label: 'SNAPSHOT', accent: 'border-temporal/50', headerBg: 'bg-temporal/10', icon: '����', iconColor: 'text-temporal' },
    window:   { label: 'WINDOW',   accent: 'border-temporal/50', headerBg: 'bg-temporal/10', icon: '���',  iconColor: 'text-temporal' },
    loop:     { label: 'LOOP',     accent: 'border-ignite/50',   headerBg: 'bg-ignite/10',   icon: '���',  iconColor: 'text-ignite'   },
    step:     { label: 'STEP',     accent: 'border-temporal/50', headerBg: 'bg-temporal/10', icon: '���',  iconColor: 'text-temporal'   },
    escape:   { label: 'ESCAPE',   accent: 'border-escape/50',   headerBg: 'bg-escape/10',   icon: '���',  iconColor: 'text-escape'    },
    invariant: { label: 'INVARIANT', accent: 'border-oof/50',    headerBg: 'bg-oof/10',      icon: '���',  iconColor: 'text-oof'  },
  }

  $: meta = NODE_KIND_META[node.kind] ?? {
    label: node.kind.toUpperCase(), accent: 'border-ink-line/80',
    headerBg: 'bg-ink-3/40', icon: '?', iconColor: 'text-warm/40',
  }

  // Max props to show in card body
  const MAX_VISIBLE_PROPS = 2
  $: propEntries = Object.entries(node.props).slice(0, MAX_VISIBLE_PROPS)
  $: hasMoreProps = Object.keys(node.props).length > MAX_VISIBLE_PROPS

  // ������ Drag handling ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������

  let dragStartX = 0
  let dragStartY = 0
  let dragging = false

  function onMouseDown(e: MouseEvent) {
    if ((e.target as HTMLElement).closest('[data-port]')) return
    e.stopPropagation()
    dispatch('select', node.id)
    dragging = true
    dragStartX = e.clientX
    dragStartY = e.clientY

    const onMove = (me: MouseEvent) => {
      if (!dragging) return
      dispatch('dragmove', { id: node.id, dx: me.clientX - dragStartX, dy: me.clientY - dragStartY })
      dragStartX = me.clientX
      dragStartY = me.clientY
    }
    const onUp = () => {
      dragging = false
      dispatch('dragend', { id: node.id })
      window.removeEventListener('mousemove', onMove)
      window.removeEventListener('mouseup', onUp)
    }
    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup', onUp)
  }

  // ������ Port events ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

  function onPortDown(e: MouseEvent, port: Port, kind: 'in'|'out') {
    e.stopPropagation()
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect()
    dispatch('portdown', {
      nodeId: node.id,
      portId: port.id,
      x: rect.left + rect.width / 2,
      y: rect.top  + rect.height / 2,
      kind,
    })
  }

  function onPortUp(e: MouseEvent, port: Port) {
    e.stopPropagation()
    dispatch('portup', { nodeId: node.id, portId: port.id })
  }
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div
  class="w-full h-full rounded-lg border-2 shadow-2xl cursor-grab active:cursor-grabbing
         bg-ink-1 transition-all select-none font-mono
         {error ? 'border-oof ring-1 ring-oof' : meta.accent}
         {selected ? 'ring-2 ring-ignite/60 shadow-ignite/10' : ''}
         {dimmed ? 'opacity-30' : 'opacity-100'}"
  on:mousedown={onMouseDown}
>
  <!-- Header -->
  <div class="flex items-center gap-1.5 px-2.5 py-1.5 rounded-t-md {meta.headerBg} border-b border-ink-line/30">
    <span class="text-[11px] {meta.iconColor} flex-shrink-0">{meta.icon}</span>
    <span class="text-[9px] font-bold uppercase tracking-widest {meta.iconColor} flex-shrink-0 opacity-70">
      {meta.label}
    </span>
    <span class="text-[11px] font-semibold text-warm-3 truncate flex-1 ml-1" title={node.name}>
      {node.name}
    </span>
    {#if error}
      <span class="text-oof font-bold text-[10px]" title={error}>���</span>
    {/if}
    <!-- Source link -->
    <button
      title="Go to line {node.sourceLine}"
      on:click|stopPropagation={() => dispatch('gotosource', node.sourceLine)}
      class="text-warm/40 hover:text-warm-3 text-[9px] flex-shrink-0 transition-colors cursor-pointer"
    >:{node.sourceLine}</button>
  </div>

  <!-- Ports row -->
  {#if node.inPorts.length > 0 || node.outPorts.length > 0}
    {@const maxPorts = Math.max(node.inPorts.length, node.outPorts.length)}
    <div class="px-0 py-1">
      {#each { length: maxPorts } as _, i}
        <div class="flex items-center justify-between" style="height: 24px">
          <!-- In port -->
          {#if node.inPorts[i]}
            {@const port = node.inPorts[i]}
            <!-- svelte-ignore a11y_no_static_element_interactions -->
            <div
              data-port="in"
              class="flex items-center gap-1 cursor-crosshair -ml-[7px] pl-0.5 pr-1.5 group"
              on:mousedown={(e) => onPortDown(e, port, 'in')}
              on:mouseup={(e) => onPortUp(e, port)}
            >
              <div class="w-3 h-3 rounded-full border border-ink-line bg-ink-3
                          group-hover:border-ignite group-hover:bg-ignite/25
                          flex-shrink-0 transition-colors"></div>
              <span class="text-[10px] text-warm/50 truncate max-w-16 group-hover:text-warm-3
                           transition-colors" title={port.label}>
                {port.label}
              </span>
            </div>
          {:else}
            <div></div>
          {/if}

          <!-- Out port -->
          {#if node.outPorts[i]}
            {@const port = node.outPorts[i]}
            <!-- svelte-ignore a11y_no_static_element_interactions -->
            <div
              data-port="out"
              class="flex items-center gap-1 cursor-crosshair -mr-[7px] pr-0.5 pl-1.5 group"
              on:mousedown={(e) => onPortDown(e, port, 'out')}
              on:mouseup={(e) => onPortUp(e, port)}
            >
              <span class="text-[10px] text-warm/50 truncate max-w-16 group-hover:text-warm-3
                           transition-colors text-right" title={port.label}>
                {port.label}
              </span>
              <div class="w-3 h-3 rounded-full border border-ink-line bg-ink-3
                          group-hover:border-ignite group-hover:bg-ignite/25
                          flex-shrink-0 transition-colors"></div>
            </div>
          {:else}
            <div></div>
          {/if}
        </div>
      {/each}
    </div>
  {/if}

  <!-- Interactive Input Field -->
  {#if node.kind === 'input'}
    <div class="px-2.5 pb-2">
      <!-- svelte-ignore a11y_autofocus -->
      <input
        type="text"
        value={inputValue}
        on:input={(e) => {
          if (e.target instanceof HTMLInputElement) {
            dispatch('inputValueChange', { name: node.name, value: e.target.value })
          }
        }}
        on:keydown|stopPropagation
        class="w-full bg-ink-3 border border-ink-line/80 rounded px-1.5 py-0.5 text-[10px] text-warm-3 outline-none focus:border-ignite"
        placeholder="Enter value..."
      />
    </div>
  {/if}

  <!-- Props (truncated) -->
  {#if propEntries.length > 0}
    <div class="border-t border-ink-line/30 px-2.5 py-1 space-y-0.5">
      {#each propEntries as [k, v]}
        <div class="flex gap-1 text-[9px] leading-tight">
          <span class="text-warm/40 flex-shrink-0">{k}:</span>
          <span class="text-warm/70 truncate" title={v}>{v}</span>
        </div>
      {/each}
      {#if hasMoreProps}
        <div class="text-[9px] text-warm/30">���</div>
      {/if}
    </div>
  {/if}

  <!-- Evaluated Value Banner -->
  {#if evaluatedValue && node.kind !== 'input'}
    <div class="border-t border-ink-line/30 px-2.5 py-1 flex items-center justify-between text-[10px] bg-ink-3/20">
      <span class="text-warm/40">Value:</span>
      <span class="font-mono font-medium truncate max-w-[120px] {node.kind === 'output' ? 'text-ember' : 'text-core'}" title={evaluatedValue}>
        {evaluatedValue}
      </span>
    </div>
  {/if}

  <!-- Error Banner -->
  {#if error}
    <div class="border-t border-oof/30 px-2.5 py-1 flex items-start gap-1 text-[9px] bg-oof/10 text-oof/90 leading-tight">
      <span class="font-bold">���</span>
      <span class="truncate" title={error}>{error}</span>
    </div>
  {/if}
</div>
