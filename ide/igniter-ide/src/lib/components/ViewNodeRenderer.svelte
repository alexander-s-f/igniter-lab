<script lang="ts">
  import ViewNodeRenderer from './ViewNodeRenderer.svelte'
  import { sanitizeNode } from '$lib/safe_renderer_policy'
  import type { ViewNode } from '$lib/safe_renderer_policy'
  import { evaluateDisplayRule } from '$lib/gui_interaction_ir'

  // Svelte 5 prop destructuring
  let {
    node,
    onSelectNode,
    selectedNode = null,
    isRoot = false,
    activeUIState = {},
    onTriggerInteraction = null
  }: {
    node: ViewNode
    onSelectNode: (node: ViewNode) => void
    selectedNode: ViewNode | null
    isRoot?: boolean
    activeUIState?: Record<string, any>
    onTriggerInteraction?: ((node: ViewNode, eventName: string) => void) | null
  } = $props()

  // Reactively sanitize the node using the shared policy (VCON-2)
  let sanitizedNode = $derived(sanitizeNode(node, isRoot))

  // Reactively evaluate display rules compiled from View DSL (VDSL-IR-7)
  let displayPatch = $derived.by(() => {
    let classes = ''
    let aria: Record<string, any> = {}

    if (sanitizedNode.display_rules) {
      sanitizedNode.display_rules.forEach((rule: any) => {
        // Pass slot_values as empty since UIState is evaluated separately
        const res = evaluateDisplayRule(rule, activeUIState, {}, sanitizedNode.node_params || {})
        if (res.success && res.effect) {
          if (res.effect.c) classes += ' ' + res.effect.c;
          if (res.effect.a) aria = { ...aria, ...res.effect.a };
        }
      })
    }
    return { classes, aria }
  })

  function handleClick(e: MouseEvent) {
    e.stopPropagation()
    onSelectNode(sanitizedNode)

    // Trigger local interaction rule evaluator if configured (VDSL-IR-7)
    if (onTriggerInteraction && sanitizedNode.interaction_rules) {
      onTriggerInteraction(sanitizedNode, 'click')
    }
  }

  // Check if selectedNode matches the current sanitizedNode by tag and attributes
  let isSelected = $derived(
    selectedNode?.tag === sanitizedNode?.tag &&
    selectedNode?.component_name === sanitizedNode?.component_name &&
    JSON.stringify(selectedNode?.attributes) === JSON.stringify(sanitizedNode?.attributes)
  )
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div
  class="relative group/node cursor-pointer transition-all duration-150 {isSelected ? 'outline-2 outline-ignite outline-offset-1 rounded-sm' : ''} {sanitizedNode && sanitizedNode.state_slots && sanitizedNode.state_slots.length > 0 ? 'border border-dashed border-temporal/30 p-1.5 rounded-sm' : ''}"
  onclick={handleClick}
>
  {#if sanitizedNode}
    <!-- Warn about stripped attributes visually in preview (VCON-6) -->
    {#if sanitizedNode.blockedAttrs.length > 0}
      <span class="absolute -top-2 right-2 bg-oof text-ink-1 text-[8px] font-bold px-1 rounded uppercase tracking-wider select-none z-10 shadow-md">
        ������ stripped attrs
      </span>
    {/if}

    <!-- State slots preflight visualization badge (VSLOT-1) -->
    {#if sanitizedNode.state_slots && sanitizedNode.state_slots.length > 0}
      <span class="absolute -bottom-2 right-2 bg-temporal text-ink-1 text-[7px] font-bold px-1 rounded uppercase tracking-wider select-none z-10 shadow-sm border border-temporal/30">
        ��� slot: {sanitizedNode.state_slots.map(s => s.slot_id).join(', ')}
      </span>
    {/if}

    <!-- UI State indicator badge (VDSL-IR-3) -->
    {#if sanitizedNode.ui_states && Object.keys(sanitizedNode.ui_states).length > 0}
      <span class="absolute -bottom-2 left-2 bg-ignite text-ink-1 text-[7px] font-bold px-1 rounded uppercase tracking-wider select-none z-10 shadow-sm border border-ignite/30">
        ��� ui_state: {Object.keys(sanitizedNode.ui_states).join(', ')}
      </span>
    {/if}

    {#if sanitizedNode.isBlockedTag}
      <!-- Render blocked tags as high-visibility warnings rather than executable UI (VCON-6) -->
      <div class="border border-oof bg-oof/5 p-3 my-2 rounded text-xs text-oof font-mono relative flex flex-col gap-1 select-none">
        <span class="font-bold flex items-center gap-1">
          <span>������</span>
          <span>Blocked tag: &lt;{sanitizedNode.blockedTag}&gt;</span>
        </span>
        <span class="text-grey text-[10px]">Safe policy violation. This tag is disallowed in visual preview.</span>
      </div>
    {:else if sanitizedNode.tag === 'text'}
      {sanitizedNode.children[0] || ''}
    {:else if sanitizedNode.tag === 'component'}
      <div class="border border-dashed border-ignite/30 hover:border-ignite/60 p-4 my-3 bg-ink-2/30 rounded relative">
        <div class="absolute -top-2.5 left-3 bg-ink-1 border border-line px-1.5 py-0.5 text-[9px] font-bold text-ignite flex items-center gap-1.5 select-none font-mono rounded-sm shadow-md">
          <span>��� Component: {sanitizedNode.component_name}</span>
          {#if sanitizedNode.trace_metadata && sanitizedNode.trace_metadata.forms_assisted}
            <span class="bg-amber/20 text-amber text-[8px] px-1 rounded uppercase tracking-wider">DX Candidate</span>
          {/if}
        </div>
        <div class="mt-1 space-y-1">
          {#each sanitizedNode.children as child}
            {#if typeof child === 'object'}
              <ViewNodeRenderer node={child} {onSelectNode} {selectedNode} isRoot={false} {activeUIState} {onTriggerInteraction} />
            {/if}
          {/each}
        </div>
      </div>
    {:else}
      <!-- Safe dynamic element rendering (VCON-6) with evaluated display patches -->
      <svelte:element
        this={sanitizedNode.tag}
        {...sanitizedNode.attributes}
        class={(sanitizedNode.attributes.class || '') + displayPatch.classes}
        {...displayPatch.aria}
      >
        {#each sanitizedNode.children as child}
          {#if typeof child === 'object'}
            <ViewNodeRenderer node={child} {onSelectNode} {selectedNode} isRoot={false} {activeUIState} {onTriggerInteraction} />
          {:else}
            {child}
          {/if}
        {/each}
      </svelte:element>
    {/if}
  {/if}
</div>
