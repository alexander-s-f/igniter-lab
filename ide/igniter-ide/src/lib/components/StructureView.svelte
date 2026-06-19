<script lang="ts">
  import { createEventDispatcher } from 'svelte'

  export let content: string = ''
  export let filePath: string = ''

  const dispatch = createEventDispatcher<{ goToLine: number }>()

  type NodeKind =
    | 'module' | 'import' | 'contract' | 'pipeline' | 'def'
    | 'input' | 'compute' | 'output' | 'read' | 'snapshot'
    | 'window' | 'loop' | 'step' | 'escape' | 'form'

  interface StructureNode {
    kind: NodeKind
    name: string
    line: number
    detail?: string
  }

  const KIND_META: Record<NodeKind, { icon: string; color: string; label: string }> = {
    module:   { icon: '���',  color: 'text-gray-400',   label: 'module'    },
    import:   { icon: '���',  color: 'text-gray-500',   label: 'import'    },
    contract: { icon: '���',  color: 'text-blue-400',   label: 'contract'  },
    pipeline: { icon: '���',  color: 'text-cyan-400',   label: 'pipeline'  },
    def:      { icon: '��',  color: 'text-purple-400', label: 'def'       },
    input:    { icon: '���',  color: 'text-green-400',  label: 'input'     },
    compute:  { icon: '=',  color: 'text-blue-300',   label: 'compute'   },
    output:   { icon: '���',  color: 'text-emerald-400',label: 'output'    },
    read:     { icon: '���',  color: 'text-yellow-400', label: 'read'      },
    snapshot: { icon: '����', color: 'text-orange-400', label: 'snapshot'  },
    window:   { icon: '���',  color: 'text-indigo-400', label: 'window'    },
    loop:     { icon: '���',  color: 'text-pink-400',   label: 'loop'      },
    step:     { icon: '���',  color: 'text-teal-400',   label: 'step'      },
    escape:   { icon: '���',  color: 'text-red-400',    label: 'escape'    },
    form:     { icon: '���',  color: 'text-violet-400', label: 'form'      },
  }

  // Patterns ordered by specificity (more specific first)
  const PATTERNS: Array<{ kind: NodeKind; re: RegExp; nameGroup: number; detailGroup?: number }> = [
    // module MyApp.Domain
    { kind: 'module',   re: /^module\s+(\S+)/,                            nameGroup: 1 },
    // import Module.{ ... } or import Module
    { kind: 'import',   re: /^import\s+(\S+)/,                            nameGroup: 1 },
    // observed contract Name { or contract Name {
    { kind: 'contract', re: /^(?:observed\s+)?contract\s+(\w+)/,          nameGroup: 1 },
    // pipeline Name[T, U, E] {
    { kind: 'pipeline', re: /^pipeline\s+(\w+)/,                          nameGroup: 1 },
    // def name(args) -> ReturnType
    { kind: 'def',      re: /^def\s+(\w+)\s*\(/,                          nameGroup: 1 },
    // input name: Type
    { kind: 'input',    re: /^\s+input\s+(\w+)\s*:/,                      nameGroup: 1, detailGroup: undefined },
    // compute name = expr
    { kind: 'compute',  re: /^\s+compute\s+(\w+)\s*=/,                    nameGroup: 1 },
    // output name: Type
    { kind: 'output',   re: /^\s+output\s+(\w+)\s*:/,                     nameGroup: 1 },
    // read name: Type
    { kind: 'read',     re: /^\s+read\s+(\w+)\s*:/,                       nameGroup: 1 },
    // snapshot name = ... or snapshot name lifecycle
    { kind: 'snapshot', re: /^\s+snapshot\s+(\w+)/,                       nameGroup: 1 },
    // window "label" {
    { kind: 'window',   re: /^\s+window\s+"([^"]+)"/,                     nameGroup: 1 },
    // loop Name in items
    { kind: 'loop',     re: /^\s+loop\s+(\w+)\s+in\s+/,                   nameGroup: 1 },
    // step name: function
    { kind: 'step',     re: /^\s+step\s+(\w+)\s*:/,                       nameGroup: 1 },
    // escape keyword
    { kind: 'escape',   re: /^\s+escape\s+(\w+)/,                        nameGroup: 1 },
    // form declaration (on contract line below)
    { kind: 'form',     re: /^\s+form\s+(.+)/,                            nameGroup: 1 },
  ]

  $: nodes = parseSource(content)
  $: topLevel = nodes.filter(n => TOP_LEVEL_KINDS.includes(n.kind))
  $: innerNodes = nodes.filter(n => !TOP_LEVEL_KINDS.includes(n.kind))

  const TOP_LEVEL_KINDS: NodeKind[] = ['module', 'import', 'contract', 'pipeline', 'def']

  interface Group {
    header: StructureNode | null
    kind: NodeKind
    nodes: StructureNode[]
  }

  $: groups = buildGroups(nodes)

  function parseSource(src: string): StructureNode[] {
    const result: StructureNode[] = []
    const lines = src.split('\n')
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]
      // skip comments
      if (line.trimStart().startsWith('--')) continue
      for (const { kind, re, nameGroup } of PATTERNS) {
        const m = line.match(re)
        if (m) {
          result.push({ kind, name: m[nameGroup] ?? '?', line: i + 1 })
          break
        }
      }
    }
    return result
  }

  const INNER_KINDS: NodeKind[] = ['input', 'compute', 'output', 'read', 'snapshot', 'window', 'loop', 'step', 'escape']
  const SECTION_ORDER: NodeKind[] = ['input', 'read', 'compute', 'loop', 'snapshot', 'window', 'step', 'output', 'escape']

  interface Section { kind: NodeKind; nodes: StructureNode[] }

  interface ContractGroup {
    header: StructureNode    // contract / pipeline / def
    sections: Section[]
  }

  interface FileStructure {
    moduleNode: StructureNode | null
    imports: StructureNode[]
    defs: StructureNode[]
    blocks: ContractGroup[]
  }

  $: structure = buildStructure(nodes)

  function buildStructure(ns: StructureNode[]): FileStructure {
    const moduleNode = ns.find(n => n.kind === 'module') ?? null
    const imports    = ns.filter(n => n.kind === 'import')
    const defs       = ns.filter(n => n.kind === 'def')

    const blockHeaders = ns.filter(n => n.kind === 'contract' || n.kind === 'pipeline')
    const blocks: ContractGroup[] = blockHeaders.map(header => {
      const nextHeader = blockHeaders.find(h => h.line > header.line)
      const inner = ns.filter(n =>
        INNER_KINDS.includes(n.kind) &&
        n.line > header.line &&
        (nextHeader ? n.line < nextHeader.line : true)
      )
      const sectionMap = new Map<NodeKind, StructureNode[]>()
      for (const node of inner) {
        const arr = sectionMap.get(node.kind) ?? []
        arr.push(node)
        sectionMap.set(node.kind, arr)
      }
      const sections: Section[] = SECTION_ORDER
        .filter(k => sectionMap.has(k))
        .map(k => ({ kind: k, nodes: sectionMap.get(k)! }))
      return { header, sections }
    })

    return { moduleNode, imports, defs, blocks }
  }

  function buildGroups(ns: StructureNode[]): Group[] { return [] }

  let collapsedSections = new Set<string>()
  let collapsedBlocks = new Set<number>()

  function toggleSection(key: string) {
    collapsedSections = collapsedSections.has(key)
      ? new Set([...collapsedSections].filter(k => k !== key))
      : new Set([...collapsedSections, key])
  }

  function toggleBlock(line: number) {
    collapsedBlocks = collapsedBlocks.has(line)
      ? new Set([...collapsedBlocks].filter(l => l !== line))
      : new Set([...collapsedBlocks, line])
  }

  function goTo(line: number) {
    dispatch('goToLine', line)
  }

  $: fileName = filePath ? filePath.split('/').pop() ?? '' : ''
</script>

<div class="flex flex-col h-full overflow-hidden text-xs select-none">

  {#if !content && !filePath}
    <div class="p-3 text-gray-600 italic text-[11px]">Open a file to see its structure.</div>

  {:else if structure.moduleNode === null && structure.blocks.length === 0 && structure.defs.length === 0}
    <div class="p-3 text-gray-600 italic text-[11px]">No contract nodes found.</div>

  {:else}

    <!-- File name -->
    {#if fileName}
      <div class="px-3 py-1.5 border-b border-gray-800 text-[10px] text-gray-600 truncate shrink-0">
        {fileName}
      </div>
    {/if}

    <div class="flex-1 overflow-y-auto py-1">

      <!-- Module -->
      {#if structure.moduleNode}
        <button
          on:click={() => goTo(structure.moduleNode!.line)}
          class="w-full flex items-center gap-2 px-3 py-1.5 text-left hover:bg-gray-800/40
                 transition-colors group border-b border-gray-800/40"
        >
          <span class="text-gray-600 w-3.5 text-center shrink-0">���</span>
          <span class="text-gray-500 font-mono text-[11px] truncate flex-1">{structure.moduleNode.name}</span>
          <span class="text-gray-700 text-[9px] group-hover:text-gray-500 shrink-0">{structure.moduleNode.line}</span>
        </button>
      {/if}

      <!-- Imports -->
      {#if structure.imports.length > 0}
        {@const key = 'imports'}
        <button
          on:click={() => toggleSection(key)}
          class="w-full flex items-center gap-1.5 px-2 py-0.5 text-[9px] uppercase
                 tracking-widest text-gray-600 hover:text-gray-400 hover:bg-gray-800/30
                 transition-colors font-bold mt-1"
        >
          <span class="text-[8px]">{collapsedSections.has(key) ? '���' : '���'}</span>
          <span>Imports</span>
          <span class="text-gray-700 ml-auto font-normal normal-case tracking-normal">{structure.imports.length}</span>
        </button>
        {#if !collapsedSections.has(key)}
          {#each structure.imports as node}
            <button
              on:click={() => goTo(node.line)}
              class="w-full flex items-center gap-2 px-4 py-0.5 text-left hover:bg-gray-800/40
                     transition-colors group"
            >
              <span class="text-gray-600 w-3 text-center shrink-0 text-[10px]">���</span>
              <span class="text-gray-500 font-mono truncate flex-1 text-[10px]">{node.name}</span>
              <span class="text-gray-700 text-[9px] group-hover:text-gray-500 shrink-0">{node.line}</span>
            </button>
          {/each}
        {/if}
      {/if}

      <!-- Standalone defs -->
      {#if structure.defs.length > 0}
        {@const key = 'defs'}
        <button
          on:click={() => toggleSection(key)}
          class="w-full flex items-center gap-1.5 px-2 py-0.5 text-[9px] uppercase
                 tracking-widest text-gray-600 hover:text-gray-400 hover:bg-gray-800/30
                 transition-colors font-bold mt-1"
        >
          <span class="text-[8px]">{collapsedSections.has(key) ? '���' : '���'}</span>
          <span>Functions</span>
          <span class="text-gray-700 ml-auto font-normal normal-case tracking-normal">{structure.defs.length}</span>
        </button>
        {#if !collapsedSections.has(key)}
          {#each structure.defs as node}
            <button
              on:click={() => goTo(node.line)}
              class="w-full flex items-center gap-2 px-4 py-1 text-left hover:bg-gray-800/40
                     transition-colors group"
            >
              <span class="text-purple-400 w-3 text-center shrink-0 font-mono">��</span>
              <span class="text-gray-300 group-hover:text-white font-mono truncate flex-1">{node.name}</span>
              <span class="text-gray-700 text-[9px] group-hover:text-gray-500 shrink-0">{node.line}</span>
            </button>
          {/each}
        {/if}
      {/if}

      <!-- Contract / Pipeline blocks -->
      {#each structure.blocks as block}
        {@const blockMeta = KIND_META[block.header.kind]}
        {@const isCollapsed = collapsedBlocks.has(block.header.line)}

        <!-- Block header -->
        <button
          on:click={() => toggleBlock(block.header.line)}
          class="w-full flex items-center gap-2 px-3 py-1.5 text-left transition-colors
                 hover:bg-gray-800/50 group mt-1 border-t border-gray-800/40"
        >
          <span class="text-[9px] text-gray-600">{isCollapsed ? '���' : '���'}</span>
          <span class="{blockMeta.color} w-3 text-center shrink-0">{blockMeta.icon}</span>
          <span class="text-gray-200 font-semibold truncate flex-1 text-[11px] group-hover:text-white">
            {block.header.name}
          </span>
          <span class="text-[9px] text-gray-600 shrink-0">{blockMeta.label}</span>
          <span class="text-gray-700 text-[9px] group-hover:text-gray-500 shrink-0 ml-1">{block.header.line}</span>
        </button>

        {#if !isCollapsed}
          {#each block.sections as section}
            {@const secMeta = KIND_META[section.kind]}
            {@const secKey = `${block.header.line}:${section.kind}`}

            <!-- Section header -->
            <button
              on:click={() => toggleSection(secKey)}
              class="w-full flex items-center gap-1.5 px-6 py-0.5 text-[9px] uppercase
                     tracking-wider text-gray-700 hover:text-gray-500 hover:bg-gray-800/20
                     transition-colors font-bold"
            >
              <span class="text-[8px]">{collapsedSections.has(secKey) ? '���' : '���'}</span>
              <span class="{secMeta.color} opacity-60">{secMeta.icon}</span>
              <span>{secMeta.label}s</span>
              <span class="text-gray-700 ml-auto font-normal normal-case">{section.nodes.length}</span>
            </button>

            {#if !collapsedSections.has(secKey)}
              {#each section.nodes as node}
                <button
                  on:click={() => goTo(node.line)}
                  class="w-full flex items-center gap-2 px-7 py-0.5 text-left
                         hover:bg-gray-800/40 transition-colors group"
                >
                  <span class="{secMeta.color} w-3 text-center shrink-0 opacity-70
                               group-hover:opacity-100 transition-opacity">
                    {secMeta.icon}
                  </span>
                  <span class="text-gray-400 group-hover:text-gray-200 font-mono truncate flex-1
                               transition-colors">
                    {node.name}
                  </span>
                  <span class="text-gray-700 text-[9px] group-hover:text-gray-500 shrink-0">
                    {node.line}
                  </span>
                </button>
              {/each}
            {/if}
          {/each}
        {/if}
      {/each}

    </div>
  {/if}
</div>
