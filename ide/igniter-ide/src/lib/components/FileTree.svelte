<script lang="ts">
  import { createEventDispatcher, tick } from 'svelte'
  import { api } from '$lib/api'
  import type { FileEntry } from '$lib/types'

  export let rootDir: string = ''
  export let currentFile: string = ''

  const dispatch = createEventDispatcher<{
    fileSelected: string
    fileDeleted: string
    fileRenamed: { from: string; to: string }
  }>()

  let entries: FileEntry[] = []
  let expanded = new Set<string>()
  let loading = false
  let error = ''

  // New file state
  let showNewFile = false
  let newFileName = ''
  let newFileParent = ''
  let newFileInput: HTMLInputElement

  // Rename state
  let renamingPath = ''
  let renameValue = ''
  let renameInput: HTMLInputElement

  // Pending delete confirmation
  let pendingDelete: FileEntry | null = null

  interface DisplayRow {
    entry: FileEntry
    depth: number
  }

  function flatRows(items: FileEntry[], exp: Set<string>, depth = 0): DisplayRow[] {
    const rows: DisplayRow[] = []
    for (const item of items) {
      rows.push({ entry: item, depth })
      if (item.entry_type === 'dir' && exp.has(item.path)) {
        rows.push(...flatRows(item.children, exp, depth + 1))
      }
    }
    return rows
  }

  $: rows = flatRows(entries, expanded)

  async function loadTree() {
    if (!rootDir) return
    loading = true; error = ''
    try {
      entries = await api.listDirTree(rootDir)
    } catch (e) { error = String(e) }
    finally { loading = false }
  }

  $: if (rootDir) loadTree()

  function toggleDir(path: string) {
    if (expanded.has(path)) expanded.delete(path)
    else expanded.add(path)
    expanded = expanded
  }

  function handleClick(entry: FileEntry) {
    if (renamingPath) return
    if (entry.entry_type === 'dir') {
      toggleDir(entry.path)
    } else {
      dispatch('fileSelected', entry.path)
    }
  }

  async function startRename(entry: FileEntry, e: MouseEvent) {
    e.stopPropagation()
    renamingPath = entry.path
    renameValue = entry.name
    await tick()
    renameInput?.select()
  }

  async function confirmRename(entry: FileEntry) {
    const trimmed = renameValue.trim()
    renamingPath = ''
    if (!trimmed || trimmed === entry.name) return
    const dir = entry.path.substring(0, entry.path.lastIndexOf('/'))
    const newPath = dir + '/' + trimmed
    try {
      await api.renameFile(entry.path, newPath)
      if (entry.path === currentFile) dispatch('fileRenamed', { from: entry.path, to: newPath })
      await loadTree()
    } catch (e) { error = String(e) }
  }

  async function startNewFile(parentDir: string, e?: MouseEvent) {
    e?.stopPropagation()
    newFileParent = parentDir || rootDir
    newFileName = ''
    pendingDelete = null
    showNewFile = true
    if (parentDir) { expanded.add(parentDir); expanded = expanded }
    await tick()
    newFileInput?.focus()
  }

  async function confirmNewFile() {
    const name = newFileName.trim()
    if (!name) return
    const finalName = name.includes('.') ? name : name + '.ig'
    const path = newFileParent + '/' + finalName
    const starter = finalName.endsWith('.ig')
      ? `-- ${finalName.replace('.ig', '')}\n\ncontract ${toPascal(name.replace('.ig', ''))} {\n  \n}\n`
      : ''
    try {
      await api.createFile(path, starter)
      showNewFile = false; newFileName = ''
      await loadTree()
      dispatch('fileSelected', path)
    } catch (e) { error = String(e) }
  }

  function requestDelete(entry: FileEntry, e: MouseEvent) {
    e.stopPropagation()
    pendingDelete = entry
  }

  async function confirmDelete() {
    if (!pendingDelete) return
    const target = pendingDelete
    pendingDelete = null
    try {
      await api.deleteFile(target.path)
      if (target.path === currentFile) dispatch('fileDeleted', target.path)
      await loadTree()
    } catch (e) { error = String(e) }
  }

  function toPascal(s: string): string {
    return s.split(/[-_\s]/).map(w => w.charAt(0).toUpperCase() + w.slice(1)).join('')
  }

  function fileIcon(entry: FileEntry): string {
    if (entry.entry_type === 'dir') return '����'
    const ext = entry.extension ?? ''
    if (ext === 'ig') return '���'
    if (ext === 'json') return '{}'
    if (ext === 'md') return '����'
    if (ext === 'rb') return '����'
    if (ext === 'rs') return '���'
    if (ext === 'ts' || ext === 'js') return '���'
    if (ext === 'toml' || ext === 'yaml' || ext === 'yml') return '���'
    return '��'
  }

  export function refresh() { loadTree() }
</script>

<div class="flex flex-col h-full min-h-0 font-mono">
  <!-- Toolbar -->
  <div class="flex items-center justify-between px-2 py-1.5 border-b border-ink-line shrink-0">
    <span class="text-xs text-warm font-semibold uppercase tracking-wider">Files</span>
    <div class="flex gap-0.5">
      <button
        on:click={() => startNewFile(rootDir)}
        class="text-xs text-warm/50 hover:text-ignite px-1.5 py-0.5 rounded hover:bg-ink-2 transition-colors cursor-pointer"
        title="New file">+</button>
      <button
        on:click={loadTree}
        class="text-xs text-warm/50 hover:text-warm-3 px-1.5 py-0.5 rounded hover:bg-ink-2 transition-colors cursor-pointer"
        title="Refresh">���</button>
    </div>
  </div>

  {#if error}
    <div class="px-2 py-1 text-xs text-oof bg-oof/10 border-b border-oof/20 shrink-0 truncate" title={error}>{error}</div>
  {/if}

  <!-- Delete confirmation bar -->
  {#if pendingDelete}
    <div class="flex items-center gap-2 px-2 py-1.5 bg-oof/10 border-b border-oof/20 shrink-0 text-xs">
      <span class="text-oof truncate flex-1">Delete "{pendingDelete.name}"?</span>
      <button on:click={confirmDelete} class="text-oof hover:text-ember font-semibold cursor-pointer">Yes</button>
      <button on:click={() => pendingDelete = null} class="text-warm/50 hover:text-warm-3 cursor-pointer">No</button>
    </div>
  {/if}

  <!-- New file input -->
  {#if showNewFile}
    <div class="flex items-center gap-1.5 px-2 py-1.5 bg-ink-1 border-b border-ignite/40 shrink-0">
      <span class="text-ignite text-xs shrink-0">���</span>
      <input
        bind:this={newFileInput}
        bind:value={newFileName}
        placeholder="filename.ig"
        class="flex-1 bg-transparent text-xs text-warm-3 outline-none border-b border-ignite min-w-0"
        on:keydown={(e) => {
          if (e.key === 'Enter') confirmNewFile()
          if (e.key === 'Escape') { showNewFile = false; newFileName = '' }
        }}
      />
      <button on:click={confirmNewFile} class="text-core hover:text-warm-3 text-xs px-0.5 cursor-pointer">���</button>
      <button on:click={() => { showNewFile = false; newFileName = '' }}
        class="text-warm/40 hover:text-warm-3 text-xs px-0.5 cursor-pointer">���</button>
    </div>
  {/if}

  <!-- Tree rows -->
  <div class="flex-1 overflow-y-auto">
    {#if loading}
      <div class="px-3 py-2 text-xs text-warm/40 flex items-center gap-2">
        <span class="animate-spin inline-block">���</span> Loading...
      </div>
    {:else if rows.length === 0 && !loading}
      <div class="px-3 py-3 text-xs text-warm/40 italic">
        Empty workspace.<br/>Click + to create a file.
      </div>
    {:else}
      {#each rows as { entry, depth } (entry.path)}
        <!-- svelte-ignore a11y_click_events_have_key_events -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div
          class="group flex items-center gap-1 py-0.5 cursor-pointer text-xs transition-colors select-none
                 {entry.path === currentFile
                   ? 'bg-ignite/10 text-warm-3 font-semibold'
                   : 'text-warm hover:bg-ink-2 hover:text-warm-3'}"
          style="padding-left: {6 + depth * 12}px; padding-right: 4px"
          on:click={() => handleClick(entry)}
          on:dblclick={(e) => { if (entry.entry_type === 'file') startRename(entry, e) }}
        >
          <!-- Chevron for dirs -->
          <span class="text-warm/40 w-3 text-center shrink-0 text-[10px]">
            {#if entry.entry_type === 'dir'}
              {expanded.has(entry.path) ? '���' : '���'}
            {/if}
          </span>

          <span class="shrink-0 text-[11px]">{fileIcon(entry)}</span>

          {#if renamingPath === entry.path}
            <input
              bind:this={renameInput}
              bind:value={renameValue}
              class="flex-1 bg-transparent border-b border-ignite outline-none text-xs text-warm-3 min-w-0"
              on:click|stopPropagation
              on:keydown={(e) => {
                if (e.key === 'Enter') confirmRename(entry)
                if (e.key === 'Escape') renamingPath = ''
              }}
              on:blur={() => confirmRename(entry)}
            />
          {:else}
            <span
              class="flex-1 truncate leading-5
                     {entry.extension === 'ig' ? 'text-ember' : ''}
                     {entry.path === currentFile ? 'text-warm-3' : ''}"
            >
              {entry.name}
            </span>
          {/if}

          <!-- Hover actions -->
          {#if renamingPath !== entry.path}
            <div class="flex gap-0.5 opacity-0 group-hover:opacity-100 shrink-0 ml-0.5">
              {#if entry.entry_type === 'dir'}
                <button
                  on:click={(e) => startNewFile(entry.path, e)}
                  class="text-warm/40 hover:text-ignite w-4 text-center leading-none cursor-pointer"
                  title="New file here">+</button>
              {:else}
                <button
                  on:click={(e) => startRename(entry, e)}
                  class="text-warm/40 hover:text-escape w-4 text-center leading-none cursor-pointer"
                  title="Rename">���</button>
              {/if}
              <button
                on:click={(e) => requestDelete(entry, e)}
                class="text-warm/40 hover:text-oof w-4 text-center leading-none cursor-pointer"
                title="Delete">���</button>
            </div>
          {/if}
        </div>
      {/each}
    {/if}
  </div>
</div>
