<script lang="ts">
  import IntrospectionTreeInspectorNode from './IntrospectionTreeInspectorNode.svelte'
  import type { IntrospectionNode } from '$lib/types'

  interface TreeNode {
    node: IntrospectionNode
    children: TreeNode[]
  }

  let {
    treeNode,
    onSelectNode,
    selectedNodeId = null,
    depth = 0
  }: {
    treeNode: TreeNode
    onSelectNode: (id: string) => void
    selectedNodeId: string | null
    depth: number
  } = $props()

  let expanded = $state(true)

  function toggleExpand(e: MouseEvent) {
    e.stopPropagation()
    expanded = !expanded
  }

  function handleSelect(e: MouseEvent) {
    e.stopPropagation()
    onSelectNode(treeNode.node.id)
  }

  let hasChildren = $derived(treeNode.children && treeNode.children.length > 0)
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="font-mono text-xs select-none">
  <div
    class="flex items-center py-1 px-2 hover:bg-ink-3/40 rounded transition-colors duration-100 {selectedNodeId === treeNode.node.id ? 'bg-ignite/15 text-ignite border-l-2 border-ignite -ml-0.5' : 'text-warm'}"
    style="padding-left: {depth * 12 + 8}px"
    onclick={handleSelect}
  >
    {#if hasChildren}
      <button
        class="w-4 h-4 flex items-center justify-center text-[10px] text-warm/40 hover:text-warm-3 transition-colors shrink-0 mr-1 cursor-pointer border-none bg-transparent"
        onclick={toggleExpand}
      >
        {expanded ? '▼' : '▶'}
      </button>
    {:else}
      <span class="w-4 mr-1 shrink-0"></span>
    {/if}

    <span class="text-grey-3 font-bold">{treeNode.node.id}</span>
    <span class="text-grey/40 text-[10px] ml-1.5 font-mono">({treeNode.node.type})</span>
    
    {#if treeNode.node.slot_bound}
      <span class="ml-1.5 bg-temporal/20 text-temporal text-[8px] px-1 rounded uppercase font-bold tracking-wider">slot</span>
    {/if}
  </div>

  {#if hasChildren && expanded}
    <div class="tree-children">
      {#each treeNode.children as child}
        <IntrospectionTreeInspectorNode treeNode={child} {onSelectNode} {selectedNodeId} depth={depth + 1} />
      {/each}
    </div>
  {/if}
</div>
