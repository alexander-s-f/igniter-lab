<script lang="ts">
  import ViewTreeInspectorNode from './ViewTreeInspectorNode.svelte'

  interface ViewNode {
    tag: string
    attributes: Record<string, any>
    is_component?: boolean
    component_name?: string
    trace_metadata?: {
      context?: string[]
      forms_assisted?: boolean
    }
    children: Array<ViewNode | string>
  }

  let {
    node,
    onSelectNode,
    selectedNode = null,
    depth = 0
  }: {
    node: ViewNode
    onSelectNode: (node: ViewNode) => void
    selectedNode: ViewNode | null
    depth: number
  } = $props()

  let expanded = $state(true)

  function toggleExpand(e: MouseEvent) {
    e.stopPropagation()
    expanded = !expanded
  }

  function handleSelect(e: MouseEvent) {
    e.stopPropagation()
    onSelectNode(node)
  }

  let hasChildren = $derived(node.children && node.children.some(c => typeof c === 'object'))
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="font-mono text-xs select-none">
  <div
    class="flex items-center py-1 px-2 hover:bg-ink-3/40 rounded transition-colors duration-100 {selectedNode === node ? 'bg-ignite/15 text-ignite border-l-2 border-ignite -ml-0.5' : 'text-warm'}"
    style="padding-left: {depth * 12 + 8}px"
    onclick={handleSelect}
  >
    {#if hasChildren}
      <button
        class="w-4 h-4 flex items-center justify-center text-[10px] text-warm/40 hover:text-warm-3 transition-colors shrink-0 mr-1 cursor-pointer"
        onclick={toggleExpand}
      >
        {expanded ? '���' : '���'}
      </button>
    {:else}
      <span class="w-4 mr-1 shrink-0"></span>
    {/if}

    {#if node.tag === 'text'}
      <span class="text-grey/60 font-sans italic truncate max-w-48">"{node.children[0]}"</span>
    {:else if node.tag === 'component'}
      <span class="text-ignite font-bold">��� {node.component_name}</span>
      {#if node.trace_metadata && node.trace_metadata.forms_assisted}
        <span class="ml-1.5 bg-amber/20 text-amber text-[8px] px-1 rounded uppercase scale-90 select-none">form</span>
      {/if}
    {:else}
      <span class="text-grey-3">&lt;{node.tag}</span>
      {#if node.attributes && Object.keys(node.attributes).length > 0}
        <span class="text-grey/50 text-[10px] ml-1">...</span>
      {/if}
      <span class="text-grey-3">&gt;</span>
    {/if}
  </div>

  {#if hasChildren && expanded}
    <div class="tree-children">
      {#each node.children as child}
        {#if typeof child === 'object'}
          <ViewTreeInspectorNode node={child} {onSelectNode} {selectedNode} depth={depth + 1} />
        {/if}
      {/each}
    </div>
  {/if}
</div>
