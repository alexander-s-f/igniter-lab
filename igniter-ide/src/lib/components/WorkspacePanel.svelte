<script lang="ts">
  import { createEventDispatcher } from 'svelte'
  import { open as openDialog } from '@tauri-apps/plugin-dialog'
  import { api } from '$lib/api'
  import type { WorkspaceConfig, WorkspaceLoadResult } from '$lib/types'
  import FileTree from './FileTree.svelte'

  export let workspace: WorkspaceConfig | null = null
  export let currentFile: string = ''

  const dispatch = createEventDispatcher<{
    opened: WorkspaceConfig
    fileSelected: string
    fileDeleted: string
    fileRenamed: { from: string; to: string }
    contracted: void
    newFile: void
  }>()

  // State machine: idle | picking | confirm_init | creating | loading | open
  type Phase = 'idle' | 'picking' | 'confirm_init' | 'creating' | 'loading' | 'open'
  // Start in 'open' if workspace prop is already set (e.g. after panel re-mount)
  let phase: Phase = workspace ? 'open' : 'idle'

  let pendingDir = ''          // dir picked, waiting for init confirmation
  let initName = ''            // name for new workspace
  let initBackend = 'in_memory'
  let error = ''
  let loadResults: WorkspaceLoadResult[] = []
  let showResults = false
  let collapsed = false

  // ������ Step 1: open native folder picker ������������������������������������������������������������������������������������������������������������������
  async function pickFolder() {
    phase = 'picking'
    error = ''
    try {
      const selected = await openDialog({ directory: true, multiple: false, title: 'Open Workspace Folder' })
      if (!selected || typeof selected !== 'string') { phase = 'idle'; return }

      pendingDir = selected
      // Try loading existing workspace first
      try {
        const config = await api.openWorkspace(pendingDir)
        await applyWorkspace(config)
      } catch (e) {
        const msg = String(e)
        if (msg.includes('No workspace found') || msg.includes('not found')) {
          // No workspace.json ��� offer to initialise
          initName = pendingDir.split('/').pop() ?? 'my-workspace'
          phase = 'confirm_init'
        } else {
          error = msg
          phase = 'idle'
        }
      }
    } catch (e) {
      error = String(e)
      phase = 'idle'
    }
  }

  // ������ Step 2a: initialise new workspace ������������������������������������������������������������������������������������������������������������������
  async function initWorkspace() {
    phase = 'creating'
    error = ''
    try {
      const config = await api.createWorkspace(pendingDir, initName)
      await applyWorkspace(config)
    } catch (e) {
      error = String(e)
      phase = 'idle'
    }
  }

  // ������ Step 2b: cancel init ���������������������������������������������������������������������������������������������������������������������������������������������������������
  function cancelInit() {
    pendingDir = ''
    initName = ''
    phase = 'idle'
  }

  // ������ Apply loaded/created workspace ���������������������������������������������������������������������������������������������������������������������������
  async function applyWorkspace(config: WorkspaceConfig) {
    phase = 'loading'
    workspace = config
    dispatch('opened', config)

    if (config.auto_load && config.contracts.length > 0) {
      loadResults = await api.loadWorkspaceContracts(config)
      showResults = true
      dispatch('contracted')
    }
    phase = 'open'
  }

  // ������ Re-open (change workspace) ������������������������������������������������������������������������������������������������������������������������������������
  async function changeWorkspace() {
    workspace = null
    loadResults = []
    showResults = false
    phase = 'idle'
    await pickFolder()
  }

  const BACKEND_LABELS: Record<string, string> = {
    in_memory: '��� in-memory',
    rocksdb:   '���� RocksDB',
    remote_tcp:'���� remote TCP',
  }
</script>

<div class="flex-1 overflow-auto flex flex-col min-h-0">

  <!-- ������ IDLE / PICKING ��������������������������������������������������������������������������������������������������������������������������������������������������������� -->
  {#if phase === 'idle' || phase === 'picking'}
    <div class="p-3 space-y-3 font-mono">
      <div class="text-xs text-warm/50">No workspace open.</div>

      <button
        on:click={pickFolder}
        disabled={phase === 'picking'}
        class="w-full flex items-center gap-2 justify-center text-sm bg-ignite hover:bg-ember
               disabled:bg-ink-3 disabled:text-warm/40 px-3 py-2 rounded transition-colors text-ink font-bold cursor-pointer">
        <span class="text-base">{phase === 'picking' ? '���' : '����'}</span>
        <span>{phase === 'picking' ? 'Opening���' : 'Open Folder'}</span>
      </button>

      <p class="text-xs text-warm/60 leading-relaxed font-sans">
        Select a project folder. If it has no workspace yet, you'll be prompted to initialise one.
      </p>

      {#if error}
        <div class="text-oof text-xs bg-oof/10 rounded border border-oof/20 p-2">{error}</div>
      {/if}
    </div>

  <!-- ������ CONFIRM INIT ��������������������������������������������������������������������������������������������������������������������������������������������������������������� -->
  {:else if phase === 'confirm_init'}
    <div class="p-3 space-y-3 font-mono">
      <div class="text-xs text-escape font-semibold">��� Initialise workspace</div>
      <div class="text-xs text-warm-3/80 break-all bg-ink-1 border border-ink-line rounded p-2">
        {pendingDir}
      </div>

      <div>
        <label class="block text-xs text-warm/60 mb-1">Workspace name</label>
        <input
          bind:value={initName}
          placeholder="my-workspace"
          class="w-full bg-ink-1 border border-ink-line rounded px-2 py-1.5
                 text-sm text-warm-3 outline-none focus:border-ignite"/>
      </div>

      <div>
        <label class="block text-xs text-warm/60 mb-1">Backend</label>
        <select
          bind:value={initBackend}
          class="w-full bg-ink-1 border border-ink-line rounded px-2 py-1.5
                 text-sm text-warm-3 outline-none focus:border-ignite">
          <option value="in_memory">��� in-memory (dev / shadow)</option>
          <option value="rocksdb">���� RocksDB (persistent)</option>
          <option value="remote_tcp">���� Remote TCP (igniter-tbackend)</option>
        </select>
      </div>

      <div class="flex gap-2">
        <button
          on:click={initWorkspace}
          class="flex-1 bg-core hover:bg-core/90 text-ink rounded px-3 py-2 text-sm
                 font-semibold transition-colors cursor-pointer">
          ��� Initialise
        </button>
        <button
          on:click={cancelInit}
          class="px-3 py-2 bg-ink-2 border border-ink-line text-warm hover:text-warm-3 rounded text-sm transition-colors cursor-pointer">
          Cancel
        </button>
      </div>

      {#if error}
        <div class="text-oof text-xs bg-oof/10 p-2 rounded border border-oof/20">{error}</div>
      {/if}
    </div>

  <!-- ������ CREATING / LOADING ��������������������������������������������������������������������������������������������������������������������������������������������� -->
  {:else if phase === 'creating' || phase === 'loading'}
    <div class="p-3 space-y-2 font-mono">
      <div class="text-xs text-temporal flex items-center gap-2">
        <span class="animate-spin">���</span>
        <span>{phase === 'creating' ? 'Creating workspace���' : 'Loading contracts���'}</span>
      </div>
      {#if workspace}
        <div class="text-xs text-warm/60 truncate">���� {workspace.name}</div>
      {/if}
    </div>

  <!-- ������ OPEN ��������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������� -->
  {:else if phase === 'open' && workspace}

    <!-- Header -->
    <div class="px-3 py-2 border-b border-ink-line bg-ink-1/40 font-mono">
      <div class="flex items-center justify-between gap-1">
        <button
          on:click={() => collapsed = !collapsed}
          class="flex items-center gap-1.5 min-w-0 text-left cursor-pointer">
          <span class="text-warm/40 text-[10px]">{collapsed ? '���' : '���'}</span>
          <span class="text-xs font-bold text-warm-3 truncate">���� {workspace.name}</span>
        </button>
        <div class="flex gap-1 shrink-0">
          <button on:click={() => dispatch('newFile')} title="New File (���N)"
            class="text-warm/50 hover:text-warm-3 hover:bg-ink-2 rounded
                   text-xs w-5 h-5 flex items-center justify-center transition-colors cursor-pointer">+</button>
          <button on:click={changeWorkspace} title="Open different folder"
            class="text-warm/40 hover:text-warm-3 text-xs px-1 transition-colors cursor-pointer">���</button>
        </div>
      </div>
      {#if !collapsed}
        <div class="text-xs text-warm/60 mt-0.5 pl-4">
          {BACKEND_LABELS[workspace.backend.backend_type] ?? workspace.backend.backend_type}
        </div>
        <div class="text-xs text-warm/40 pl-4 truncate mt-0.5" title={workspace.root_dir}>
          {workspace.root_dir.split('/').slice(-3).join('/')}
        </div>
      {/if}
    </div>

    {#if !collapsed}
      <!-- Load results -->
      {#if showResults && loadResults.length > 0}
        <div class="px-3 py-2 border-b border-ink-line bg-ink-1/10 space-y-1 font-mono">
          <div class="text-xs text-warm font-semibold mb-1">Auto-loaded contracts</div>
          {#each loadResults as r}
            <div class="text-xs {r.success ? 'text-core' : 'text-oof'} flex items-start gap-1">
              <span>{r.success ? '���' : '���'}</span>
              <span class="truncate">{r.contract_name}</span>
            </div>
            {#if !r.success}
              <div class="text-warm/60 text-xs pl-4 break-words">{r.message.slice(0,80)}</div>
            {/if}
          {/each}
          <button on:click={() => showResults = false}
            class="text-xs text-warm/50 hover:text-warm-3 mt-1 cursor-pointer">Dismiss ��</button>
        </div>
      {/if}

      <!-- File tree -->
      <div class="flex-1 min-h-0 overflow-hidden border-t border-ink-line">
        <FileTree
          rootDir={workspace.root_dir}
          {currentFile}
          on:fileSelected={(e) => dispatch('fileSelected', e.detail)}
          on:fileDeleted={(e) => dispatch('fileDeleted', e.detail)}
          on:fileRenamed={(e) => dispatch('fileRenamed', e.detail)}
        />
      </div>
    {/if}
  {/if}
</div>
