<script lang="ts">
  import { onMount } from 'svelte'
  import { api } from '$lib/api'
  import type { ContractInfo, StatusInfo, WorkspaceConfig, DiagnosticInfo, AppConfig } from '$lib/types'
  import { settings } from '$lib/stores/settings'
  import { artifacts, buildsStore, runsStore, debuggerStore } from '$lib/stores/artifacts'
  import type { RunRecord } from '$lib/stores/artifacts'

  import ContractBrowser    from '$lib/components/ContractBrowser.svelte'
  import DispatchPanel      from '$lib/components/DispatchPanel.svelte'
  import ObservationStream  from '$lib/components/ObservationStream.svelte'
  import FactExplorer       from '$lib/components/FactExplorer.svelte'
  import TemporalTimeline   from '$lib/components/TemporalTimeline.svelte'
  import ContractDAG        from '$lib/components/ContractDAG.svelte'
  import MonacoEditor       from '$lib/components/MonacoEditor.svelte'
  import WorkspacePanel     from '$lib/components/WorkspacePanel.svelte'
  import SystemGraph        from '$lib/components/SystemGraph.svelte'
  import ExecutionTracer    from '$lib/components/ExecutionTracer.svelte'
  import AppManager         from '$lib/components/AppManager.svelte'
  import SettingsModal      from '$lib/components/SettingsModal.svelte'
  import ContractInspector  from '$lib/components/ContractInspector.svelte'
  import CommandPalette     from '$lib/components/CommandPalette.svelte'
  import BuildArtifacts     from '$lib/components/BuildArtifacts.svelte'
  import ProblemsPanel      from '$lib/components/ProblemsPanel.svelte'
  import InlineRunPanel     from '$lib/components/InlineRunPanel.svelte'
  import AIAssistant        from '$lib/components/AIAssistant.svelte'
  import NewFileWizard      from '$lib/components/NewFileWizard.svelte'
  import StructureView      from '$lib/components/StructureView.svelte'
  import RecentFilesPopup   from '$lib/components/RecentFilesPopup.svelte'
  import BlueprintView      from '$lib/components/blueprint/BlueprintView.svelte'
  import WelcomeDashboard   from '$lib/components/WelcomeDashboard.svelte'
  import DocsPanel          from '$lib/components/DocsPanel.svelte'
  import DocsView           from '$lib/components/DocsView.svelte'
  import DebuggerPanel      from '$lib/components/DebuggerPanel.svelte'
  import IgMark             from '$lib/components/IgMark.svelte'
  import ViewInspector      from '$lib/components/ViewInspector.svelte'
  import ContractFormGenerator from '$lib/components/ContractFormGenerator.svelte'


  // ������ Types ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  type LeftPanelId  = 'project' | 'contracts' | 'apps' | 'docs' | 'ai'
  type RightPanelId = 'inspector' | 'structure'
  type ViewTabId    = 'dispatch' | 'dag' | 'system' | 'tracer' | 'timeline' | 'blueprint' | 'view_preview' | 'schema_form'
  type BottomTabId  = 'output' | 'observations' | 'facts' | 'artifacts' | 'problems' | 'debugger'
  type CompileStatus = 'ok' | 'error' | 'compiling'

  interface LogEntry { text: string; type: 'ok' | 'error' | 'info'; ts: string }
  interface OpenTab  { path: string; content: string; dirty: boolean; diagnostics: DiagnosticInfo[] }

  // ������ Status ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let status: StatusInfo = { backend: 'in_memory', facts_count: 0, contracts_count: 0, observations_count: 0 }
  let contracts: ContractInfo[] = []

  // ������ Left sidebar ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let leftPanel: LeftPanelId | null = 'project'
  let leftWidth = 240
  let draggingLeft = false
  let dragStartX = 0
  let dragStartW = 0

  // ������ Right sidebar ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let rightPanel: RightPanelId | null = 'inspector'
  let rightWidth = 224
  let draggingRight = false
  let dragStartXR = 0
  let dragStartWR = 0

  // ������ Editor / tabs ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  type ActiveAreaId = 'editor' | ViewTabId
  let activeArea: ActiveAreaId = 'editor'

  let openTabs: OpenTab[] = []
  let activeTabPath = ''

  let editorRef: MonacoEditor
  let dagSelectedContract = ''
  let selectedContract = ''

  // ������ Auto-save ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let autoSaveTimer: ReturnType<typeof setTimeout>
  let lastSavedAt: Date | null = null
  let isSavingNow = false

  // ������ Compile status per file path ������������������������������������������������������������������������������������������������������������������������������������������
  let compileStatus: Record<string, CompileStatus> = {}

  // ������ Time ticker for relative timestamps ������������������������������������������������������������������������������������������������������������������
  let _tick = Date.now()

  $: activeTab  = openTabs.find(t => t.path === activeTabPath) ?? null
  $: errCount   = activeTab?.diagnostics.filter(d => d.severity === 'error').length   ?? 0
  $: warnCount  = activeTab?.diagnostics.filter(d => d.severity === 'warning').length ?? 0

  $: totalErrCount  = openTabs.reduce((n, t) => n + t.diagnostics.filter(d => d.severity === 'error').length, 0)
  $: totalWarnCount = openTabs.reduce((n, t) => n + t.diagnostics.filter(d => d.severity === 'warning').length, 0)

  function formatRelTime(d: Date): string {
    const secs = Math.floor((_tick - d.getTime()) / 1000)
    if (secs < 5)  return 'just now'
    if (secs < 60) return `${secs}s ago`
    return `${Math.floor(secs / 60)}m ago`
  }

  // ������ Workspace & apps ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let workspace: WorkspaceConfig | null = null
  let apps: AppConfig[] = []

  // ������ Bottom panel ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let bottomOpen   = false
  let bottomTab: BottomTabId = 'output'
  let bottomHeight = 200
  let draggingBottom = false
  let dragStartY = 0
  let dragStartH = 0

  // ������ Output log ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let outputLog: LogEntry[] = []
  let outputEnd: HTMLDivElement

  function log(text: string, type: LogEntry['type'] = 'info') {
    outputLog = [...outputLog.slice(-299), { text, type, ts: new Date().toLocaleTimeString() }]
    if (type === 'error') { bottomOpen = true; bottomTab = 'output' }
    setTimeout(() => outputEnd?.scrollIntoView({ behavior: 'smooth' }), 30)
  }

  // ������ Settings modal ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let settingsOpen = false

  // ������ Command palette ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let paletteOpen = false

  // ������ New file wizard ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let wizardOpen = false

  // ������ Recent files popup ������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let recentFilesOpen = false
  let recentFiles: string[] = []

  // ������ Inline run panel ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  let runPanelOpen = false
  $: runPanelContract = activeTabPath.split('/').pop()?.replace(/\.ig$/, '') ?? ''

  // ������ Dispatch replay inputs ������������������������������������������������������������������������������������������������������������������������������������������������������������
  let replayInputs = ''

  // ������ Panel configs ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  const LEFT_PANELS: Array<{ id: LeftPanelId; icon: string; label: string }> = [
    { id: 'project',   icon: '����', label: 'Project' },
    { id: 'contracts', icon: '���',  label: 'Contracts' },
    { id: 'apps',      icon: '���',  label: 'Apps' },
    { id: 'docs',      icon: '����', label: 'Docs & Specs' },
    { id: 'ai',        icon: '���',  label: 'AI Assistant' },
  ]

  const RIGHT_PANELS: Array<{ id: RightPanelId; icon: string; label: string }> = [
    { id: 'inspector', icon: '���', label: 'Inspector' },
    { id: 'structure', icon: '���', label: 'Structure'  },
  ]

  const VIEW_TABS: Array<{ id: ViewTabId; label: string }> = [
    { id: 'blueprint', label: '��� Blueprint' },
    { id: 'dispatch',  label: 'Dispatch' },
    { id: 'schema_form', label: '��� Form Generator' },
    { id: 'dag',       label: 'DAG' },
    { id: 'system',    label: 'System' },
    { id: 'tracer',    label: 'Tracer' },
    { id: 'timeline',  label: 'Timeline' },
    { id: 'view_preview', label: '���� View Preview' },
  ]

  const BOTTOM_TABS: Array<{ id: BottomTabId; label: string }> = [
    { id: 'output',       label: 'Output' },
    { id: 'problems',     label: 'Problems' },
    { id: 'debugger',     label: 'Debugger ���' },
    { id: 'observations', label: 'Observations' },
    { id: 'facts',        label: 'Facts' },
    { id: 'artifacts',    label: 'Artifacts' },
  ]

  // ������ Refresh ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  async function refresh() {
    try { [status, contracts] = await Promise.all([api.getStatus(), api.listContracts()]) } catch {}
  }
  async function loadApps() {
    if (!workspace) return
    try { apps = await api.listApps(workspace.root_dir) } catch {}
  }
  onMount(() => {
    refresh()
    const iv = setInterval(refresh, 3000)
    const tickIv = setInterval(() => _tick = Date.now(), 5000)
    return () => { clearInterval(iv); clearInterval(tickIv) }
  })

  // ������ Left panel toggle ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  function toggleLeft(id: LeftPanelId) {
    leftPanel = leftPanel === id ? null : id
    if (id === 'ai' && leftPanel === 'ai' && leftWidth < 320) leftWidth = 320
  }
  function toggleRight(id: RightPanelId) {
    rightPanel = rightPanel === id ? null : id
    if (id === 'structure' && rightPanel === 'structure' && rightWidth < 200) rightWidth = 200
  }

  // ������ Multi-file tab management ������������������������������������������������������������������������������������������������������������������������������������������������������
  let preselectedTemplateId = 'empty'

  function resolveRelativePath(path: string, rootDir: string | undefined): string {
    if (!rootDir || (!path.startsWith('.') && !path.startsWith('..'))) {
      return path
    }
    const rootParts = rootDir.split('/')
    const pathParts = path.split('/')
    for (const part of pathParts) {
      if (part === '.') {
        // do nothing
      } else if (part === '..') {
        rootParts.pop()
      } else {
        rootParts.push(part)
      }
    }
    return rootParts.join('/')
  }

  async function handleOpenDoc(path: string, title: string) {
    const resolvedPath = (path.startsWith('.') || path.startsWith('..')) && workspace?.root_dir
      ? resolveRelativePath(path, workspace.root_dir)
      : path
    try {
      const existing = openTabs.find(t => t.path === resolvedPath)
      if (existing) {
        if (resolvedPath !== activeTabPath) snapshotActiveTab()
        activeTabPath = resolvedPath
        activeArea = 'editor'
        trackRecent(resolvedPath)
        return
      }
      snapshotActiveTab()
      const content = await api.readFile(resolvedPath)
      openTabs = [...openTabs, { path: resolvedPath, content, dirty: false, diagnostics: [] }]
      activeTabPath = resolvedPath
      activeArea = 'editor'
      trackRecent(resolvedPath)
    } catch (e) {
      log(String(e), 'error')
    }
  }

  async function handleFileSelected(path: string) {
    try {
      const existing = openTabs.find(t => t.path === path)
      if (existing) {
        if (path !== activeTabPath) snapshotActiveTab()
        activeTabPath = path
        if (!path.endsWith('.md')) {
          editorRef?.setValue(existing.content)
        }
        activeArea = 'editor'
        trackRecent(path)
        return
      }
      snapshotActiveTab()
      const content = await api.readFile(path)
      openTabs = [...openTabs, { path, content, dirty: false, diagnostics: [] }]
      activeTabPath = path
      if (!path.endsWith('.md')) {
        editorRef?.setValue(content)
      }
      activeArea = 'editor'
      trackRecent(path)
    } catch (e) { log(String(e), 'error') }
  }

  function trackRecent(path: string) {
    recentFiles = [path, ...recentFiles.filter(p => p !== path)].slice(0, 30)
  }

  // ������ Breadcrumbs ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  $: breadcrumbs = computeBreadcrumbs(activeTabPath, workspace)

  function computeBreadcrumbs(path: string, ws: WorkspaceConfig | null): string[] {
    if (!path) return []
    if (ws?.root_dir && path.startsWith(ws.root_dir)) {
      const rel = path.slice(ws.root_dir.length + 1)
      return [ws.name, ...rel.split('/')]
    }
    return path.split('/').slice(-3)
  }

  function snapshotActiveTab() {
    // Capture current editor content into openTabs before switching away.
    if (activeTabPath && editorRef && !activeTabPath.endsWith('.md')) {
      const current = editorRef.getValue()
      openTabs = openTabs.map(t =>
        t.path === activeTabPath ? { ...t, content: current } : t)
    }
  }

  function activateTab(path: string) {
    if (path === activeTabPath) return
    snapshotActiveTab()
    const tab = openTabs.find(t => t.path === path)
    if (!tab) return
    activeTabPath = path
    activeArea = 'editor'
    if (!path.endsWith('.md')) {
      editorRef?.setValue(tab.content)
    }
  }

  function closeTab(path: string, e?: MouseEvent) {
    e?.stopPropagation()
    if (path === activeTabPath) snapshotActiveTab()
    const idx = openTabs.findIndex(t => t.path === path)
    openTabs = openTabs.filter(t => t.path !== path)
    if (activeTabPath === path) {
      const next = openTabs[idx] ?? openTabs[idx - 1] ?? null
      if (next) {
        activeTabPath = next.path
        activeArea = 'editor'
        if (!next.path.endsWith('.md')) {
          editorRef?.setValue(next.content)
        }
      }
      else {
        activeTabPath = ''
        editorRef?.setValue('')
      }
    }
  }

  function handleFileDeleted(path: string)                    { closeTab(path) }
  function handleFileRenamed(from: string, to: string)        {
    openTabs = openTabs.map(t => t.path === from ? { ...t, path: to } : t)
    if (activeTabPath === from) activeTabPath = to
  }

  async function handleEditorSave(source: string) {
    if (!activeTabPath) return
    isSavingNow = true
    try {
      await api.writeFile(activeTabPath, source)
      openTabs = openTabs.map(t =>
        t.path === activeTabPath ? { ...t, content: source, dirty: false } : t)
      lastSavedAt = new Date()
      log(`Saved: ${activeTabPath.split('/').pop()}`, 'ok')
      if ($settings.workflow?.autoCompile) await handleLoadFromEditor()
    } catch (e) { log(String(e), 'error') }
    finally { isSavingNow = false }
  }

  async function handleLoadFromEditor() {
    const source = editorRef?.getValue() ?? activeTab?.content ?? ''
    const name   = activeTabPath.split('/').pop()?.replace('.ig', '') || 'Contract'
    const path   = activeTabPath
    const ts     = Date.now()
    if (path) compileStatus = { ...compileStatus, [path]: 'compiling' }
    try {
      const result = await api.loadContract(source, name, workspace?.root_dir ?? undefined)

      artifacts.addBuild({
        contractName: name,
        ts,
        success: result.success,
        message: result.message,
        sourceLength: source.length,
        artifactPath: result.artifact_dir ?? undefined
      })

      artifacts.addDebugEvent({
        type: 'compile',
        timestamp: ts,
        contractName: name,
        success: result.success,
        durationMs: result.duration_ms,
        sourceLength: source.length,
        sourceHash: result.source_hash,
        command: 'load_contract',
        diagnosticsCount: result.diagnostics_count,
        artifactDir: result.artifact_dir ?? undefined,
        errorStage: result.error_stage ?? undefined
      })

      if (result.success) {
        if (path) compileStatus = { ...compileStatus, [path]: 'ok' }
        log(result.message, 'ok')
        selectedContract = name
        await refresh()

        // Update code intelligence index with fresh IR
        api.getContractIr(name).then(ir => editorRef?.updateContractIr(name, ir)).catch(() => {})

        // ������ Auto snapshot ������������������������������������������������������������������������������������������������������������������������������������������������������������������
        if ($settings.workflow?.autoSnapshot && path) {
          const snapshotPath = path.replace(/\.ig$/, '') + `.snap.${ts}.ig`
          api.writeFile(snapshotPath, source).catch(() => {})
        }
      } else {
        if (path) compileStatus = { ...compileStatus, [path]: 'error' }
        log(result.message, 'error')
      }
    } catch (e) {
      if (path) compileStatus = { ...compileStatus, [path]: 'error' }
      artifacts.addBuild({ contractName: name, ts, success: false, message: String(e) })
      artifacts.addDebugEvent({
        type: 'compile',
        timestamp: ts,
        contractName: name,
        success: false,
        durationMs: Date.now() - ts,
        sourceLength: source.length,
        command: 'load_contract',
        errorStage: 'emit'
      })
      log(String(e), 'error')
    }
  }

  async function handleLoadFile() {
    const input = document.createElement('input')
    input.type = 'file'; input.accept = '.ig'
    input.onchange = async (e) => {
      const file = (e.target as HTMLInputElement).files?.[0]
      if (!file) return
      const source = await file.text()
      const name   = file.name.replace(/\.ig$/, '')
      const ts     = Date.now()
      try {
        const result = await api.loadContract(source, name, workspace?.root_dir ?? undefined)

        artifacts.addBuild({
          contractName: name,
          ts,
          success: result.success,
          message: result.message,
          sourceLength: source.length,
          artifactPath: result.artifact_dir ?? undefined
        })

        artifacts.addDebugEvent({
          type: 'compile',
          timestamp: ts,
          contractName: name,
          success: result.success,
          durationMs: result.duration_ms,
          sourceLength: source.length,
          sourceHash: result.source_hash,
          command: 'load_contract_file',
          diagnosticsCount: result.diagnostics_count,
          artifactDir: result.artifact_dir ?? undefined,
          errorStage: result.error_stage ?? undefined
        })

        if (result.success) {
          log(result.message, 'ok')
          await refresh()
        } else {
          log(result.message, 'error')
        }
      } catch (err) {
        artifacts.addBuild({ contractName: name, ts, success: false, message: String(err) })
        artifacts.addDebugEvent({
          type: 'compile',
          timestamp: ts,
          contractName: name,
          success: false,
          durationMs: Date.now() - ts,
          sourceLength: source.length,
          command: 'load_contract_file',
          errorStage: 'emit'
        })
        log(String(err), 'error')
      }
    }
    input.click()
  }

  // ������ Workspace indexing ������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  async function indexWorkspace(config: WorkspaceConfig) {
    try {
      const files = await api.listIgFiles(config.root_dir)
      const names: string[] = []
      const contractFiles: Record<string, string> = {}
      for (const f of files) {
        const name = f.split('/').pop()?.replace(/\.ig$/, '')
        if (name) { names.push(name); contractFiles[name] = f }
      }
      editorRef?.setWorkspaceIndex(names, [], contractFiles)
    } catch {}
  }

  // ������ Jump to file:line (from ProblemsPanel) ������������������������������������������������������������������������������������������������������������
  async function handleJumpToLine(path: string, line: number) {
    await handleFileSelected(path)
    // small delay to let editor mount
    setTimeout(() => editorRef?.goToLine(line), 80)
  }

  // ������ DAG drill-down ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  function handleDrillDown(contractName: string) { dagSelectedContract = contractName; activeArea = 'dag' }

  // ������ Inspector events ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  function handleInspectorDag(contractName: string) {
    dagSelectedContract = contractName; activeArea = 'dag'
  }
  function handleInspectorDispatch(contractName: string) {
    selectedContract = contractName; activeArea = 'dispatch'
  }

  // ������ Command palette handling ���������������������������������������������������������������������������������������������������������������������������������������������������������
  function handlePaletteCommand(id: string) {
    const viewId = id.replace('view.', '')
    if (['dispatch','dag','system','tracer','timeline','blueprint'].includes(viewId)) {
      activeArea = viewId as ActiveAreaId
    }
    paletteOpen = false
  }

  // ������ Replay a past run ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  function handleReplay(run: RunRecord) {
    replayInputs    = JSON.stringify(run.inputs ?? {}, null, 2)
    selectedContract = run.contractName
    activeArea      = 'dispatch'
    bottomOpen      = false
  }
  $: if (activeArea !== 'dispatch') replayInputs = ''

  // ������ Drag: left panel resize ���������������������������������������������������������������������������������������������������������������������������������������������������������
  function startLeftDrag(e: MouseEvent)   { draggingLeft  = true; dragStartX  = e.clientX; dragStartW  = leftWidth;  e.preventDefault() }
  function startRightDrag(e: MouseEvent)  { draggingRight = true; dragStartXR = e.clientX; dragStartWR = rightWidth; e.preventDefault() }
  function startBottomDrag(e: MouseEvent) { draggingBottom = true; dragStartY = e.clientY; dragStartH  = bottomHeight; e.preventDefault() }

  function onMouseMove(e: MouseEvent) {
    if (draggingLeft)   leftWidth    = Math.max(160, Math.min(520, dragStartW  + (e.clientX  - dragStartX)))
    if (draggingBottom) bottomHeight = Math.max(80,  Math.min(500, dragStartH  + (dragStartY - e.clientY)))
    if (draggingRight)  rightWidth   = Math.max(160, Math.min(460, dragStartWR + (dragStartXR - e.clientX)))
  }
  function onMouseUp() { draggingLeft = false; draggingBottom = false; draggingRight = false }

  // ������ Global keyboard ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  function onKeydown(e: KeyboardEvent) {
    const mod = e.metaKey || e.ctrlKey
    if (mod && e.key === 'k') { e.preventDefault(); paletteOpen = true }
    if (mod && e.key === ',') { e.preventDefault(); settingsOpen = true }
    if (mod && !e.shiftKey && e.key === 'n') { e.preventDefault(); wizardOpen = true }
    if (mod && !e.shiftKey && e.key === 'e') { e.preventDefault(); recentFilesOpen = true }
    if (mod && !e.shiftKey && e.key === 'b') { e.preventDefault(); leftPanel = leftPanel ? null : 'project' }
    if (mod && !e.shiftKey && e.key === 'j') { e.preventDefault(); bottomOpen = !bottomOpen; if (bottomOpen && bottomTab === 'problems') {} }
    if (mod && e.shiftKey && e.key.toLowerCase() === 'm') {
      e.preventDefault(); bottomOpen = true; bottomTab = 'problems'
    }
    if (mod && e.shiftKey && e.key.toLowerCase() === 'b') {
      e.preventDefault()
      if (activeArea === 'editor') handleLoadFromEditor()
    }
    if (mod && e.key === 'Enter' && activeArea === 'editor') {
      e.preventDefault()
      if (runPanelContract) runPanelOpen = !runPanelOpen
    }
  }

  // Force Monaco layout when editor becomes visible
  $: if (activeArea === 'editor' && editorRef) setTimeout(() => editorRef?.layout?.(), 50)

  // ������ Derived ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
  $: logErrCount = outputLog.filter(l => l.type === 'error').length

  const LOG_COLORS: Record<LogEntry['type'], string> = {
    ok: 'text-core', error: 'text-oof', info: 'text-warm',
  }
</script>

<svelte:window on:mousemove={onMouseMove} on:mouseup={onMouseUp} on:keydown={onKeydown} />

<!-- Settings modal -->
<SettingsModal bind:open={settingsOpen} />

<!-- Command palette overlay -->
<CommandPalette
  bind:open={paletteOpen}
  {contracts}
  on:command={(e) => handlePaletteCommand(e.detail.id)}
  on:openDispatch={(e) => handleInspectorDispatch(e.detail)}
  on:close={() => paletteOpen = false}
/>

<!-- New file wizard -->
<NewFileWizard
  bind:open={wizardOpen}
  workspaceDir={workspace?.root_dir ?? ''}
  currentFilePath={activeTabPath}
  preselectedTemplateId={preselectedTemplateId}
  on:created={(e) => handleFileSelected(e.detail)}
  on:close={() => wizardOpen = false}
/>

<!-- Recent files popup -->
<RecentFilesPopup
  bind:open={recentFilesOpen}
  files={recentFiles}
  on:select={(e) => handleFileSelected(e.detail)}
  on:close={() => recentFilesOpen = false}
/>

<div
  class="flex flex-col h-screen bg-ink text-warm-3 font-mono overflow-hidden select-none"
  class:cursor-col-resize={draggingLeft || draggingRight}
  class:cursor-ns-resize={draggingBottom}
>
  <div class="flex flex-1 overflow-hidden">

    <!-- ������ LEFT ICON STRIP ������������������������������������������������������������������������������������������������������������������������������������������������������������������ -->
    <nav class="w-10 shrink-0 bg-ink-1 border-r border-ink-line flex flex-col items-center py-1">
      <div class="flex flex-col items-center gap-0.5 flex-1 w-full">
        {#each LEFT_PANELS as p}
          <button title={p.label} on:click={() => toggleLeft(p.id)}
            class="w-8 h-8 flex items-center justify-center rounded text-sm transition-colors cursor-pointer relative
                   {leftPanel === p.id ? 'bg-ignite/15 text-ignite' : 'text-warm hover:text-warm-3 hover:bg-ink-2'}">
            {p.icon}
            {#if leftPanel === p.id}
              <span class="absolute left-0 top-1.5 bottom-1.5 w-0.5 bg-ignite rounded-r"></span>
            {/if}
          </button>
        {/each}
      </div>
      <button title="Settings (���,)" on:click={() => settingsOpen = true}
        class="w-8 h-8 mb-1 flex items-center justify-center rounded text-lg transition-colors cursor-pointer
               text-warm hover:text-warm-3 hover:bg-ink-2">
        ���
      </button>
    </nav>

    <!-- ������ LEFT PANEL (collapsible, drag-resizable) ������������������������������������������������������������������������������������ -->
    {#if leftPanel}
      <aside
        class="relative shrink-0 bg-ink border-r border-ink-line flex flex-col overflow-hidden"
        style="width: {leftWidth}px"
      >
        <div class="flex items-center justify-between px-2 py-1 border-b border-ink-line shrink-0 bg-ink-1">
          <span class="text-xs font-bold text-warm uppercase tracking-wider font-mono">
            {LEFT_PANELS.find(p => p.id === leftPanel)?.label ?? leftPanel}
          </span>
          <button on:click={() => leftPanel = null}
            class="text-warm/50 hover:text-warm-3 text-xs w-4 h-4 flex items-center justify-center cursor-pointer">���</button>
        </div>

        <div class="flex-1 overflow-hidden flex flex-col min-h-0">
          {#if leftPanel === 'project'}
            <WorkspacePanel
              {workspace}
              currentFile={activeTabPath}
              on:opened={(e) => { workspace = e.detail; refresh(); loadApps(); indexWorkspace(e.detail) }}
              on:fileSelected={(e) => handleFileSelected(e.detail)}
              on:fileDeleted={(e) => handleFileDeleted(e.detail)}
              on:fileRenamed={(e) => handleFileRenamed(e.detail.from, e.detail.to)}
              on:contracted={refresh}
              on:newFile={() => wizardOpen = true}
            />
          {:else if leftPanel === 'contracts'}
            <div class="flex flex-col h-full min-h-0">
              <div class="flex items-center justify-between px-2 py-1.5 border-b border-gray-800 shrink-0">
                <span class="text-xs text-gray-500">{contracts.length} loaded</span>
                <button on:click={handleLoadFile}
                  class="text-xs bg-blue-700 hover:bg-blue-600 px-2 py-0.5 rounded transition-colors">+ Load .ig</button>
              </div>
              <div class="flex-1 overflow-y-auto">
                <ContractBrowser {contracts} bind:selected={selectedContract} />
              </div>
            </div>
          {:else if leftPanel === 'apps'}
            <div class="flex-1 overflow-y-auto p-2">
              {#if workspace}
                <AppManager workspaceDir={workspace.root_dir} {apps} on:appsChanged={(e) => apps = e.detail} />
              {:else}
                <p class="text-xs text-gray-600 p-2">Open a workspace first.</p>
              {/if}
            </div>
          {:else if leftPanel === 'docs'}
            <DocsPanel
              on:selectChapter={(e) => handleOpenDoc(e.detail.path, e.detail.title)}
            />
          {:else if leftPanel === 'ai'}
            <AIAssistant
              editorContent={activeTab?.content ?? (editorRef?.getValue() ?? '')}
              filePath={activeTabPath}
              diagnostics={activeTab?.diagnostics ?? []}
              on:insertCode={(e) => editorRef?.insertText(e.detail)}
              on:replaceFile={(e) => {
                editorRef?.setValue(e.detail)
                if (activeTabPath) {
                  openTabs = openTabs.map(t =>
                    t.path === activeTabPath ? { ...t, content: e.detail, dirty: true } : t)
                }
              }}
            />
          {/if}
        </div>

        <!-- Right edge drag handle -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div class="absolute right-0 top-0 bottom-0 w-1 cursor-col-resize z-10
                    hover:bg-ignite/30 active:bg-ignite/50 transition-colors"
             on:mousedown={startLeftDrag}></div>
      </aside>
    {/if}

    <!-- ������ MAIN AREA ��������������������������������������������������������������������������������������������������������������������������������������������������������������������������������� -->
    <main class="flex-1 flex flex-col overflow-hidden min-w-0">

      <!-- ������ ROW 1: Editor file tabs ������������������������������������������������������������������������������������������������������������������������������������ -->
      <div class="flex items-end bg-ink-1 border-b border-ink-line shrink-0 overflow-x-auto min-h-9">

        <!-- Empty state hint when no files open -->
        {#if openTabs.length === 0}
          <div class="flex items-center px-3 py-2 text-xs text-warm/50 italic select-none">
            {activeArea === 'editor' ? 'No files open' : ''}
          </div>
        {/if}

        <!-- File tabs -->
        {#each openTabs as tab (tab.path)}
          {@const isActive = activeArea === 'editor' && activeTabPath === tab.path}
          <div
            role="button" tabindex="0"
            on:click={() => activateTab(tab.path)}
            on:keydown={(e) => e.key === 'Enter' && activateTab(tab.path)}
            on:auxclick={(e) => e.button === 1 && closeTab(tab.path)}
            class="flex items-center gap-1.5 px-3 py-2 text-xs cursor-pointer select-none
                   border-r border-ink-line shrink-0 transition-colors group min-w-0
                   {isActive
                     ? 'bg-ink text-warm-3 border-t-2 border-t-ignite -mb-px pb-2.25'
                     : 'text-warm hover:text-warm-3 hover:bg-ink-2'}"
          >
            {#if tab.path.endsWith('.md')}
              <span class="text-temporal text-[10px]">����</span>
            {:else if compileStatus[tab.path] === 'ok'}
              <span class="text-core text-[10px]">���</span>
            {:else if compileStatus[tab.path] === 'error'}
              <span class="text-oof text-[10px]">���</span>
            {:else if compileStatus[tab.path] === 'compiling'}
              <span class="text-temporal text-[10px] animate-pulse">���</span>
            {:else}
              <span class="text-temporal text-[10px]">���</span>
            {/if}
            <span class="max-w-28 truncate">{tab.path.split('/').pop()}</span>
            {#if tab.dirty}<span class="text-ember text-[10px]">���</span>{/if}
            <button
              on:click|stopPropagation={(e) => closeTab(tab.path, e)}
              class="ml-0.5 text-warm/40 group-hover:text-warm/80 hover:text-warm-3!
                     leading-none w-3.5 h-3.5 flex items-center justify-center transition-colors cursor-pointer">���</button>
          </div>
        {/each}

        <div class="flex-1 min-w-2"></div>

        <!-- ���K + Compile -->
        <button
          on:click={() => paletteOpen = true}
          class="px-2 py-1 mx-1 my-1 text-warm/50 hover:text-warm-3 hover:bg-ink-2
                 rounded text-xs transition-colors shrink-0 cursor-pointer"
          title="Command Palette (���K)">���K</button>

        {#if activeArea === 'editor'}
          <button
            on:click={handleLoadFromEditor}
            class="px-2.5 py-1 my-1 bg-ignite/15 hover:bg-ignite/25 text-ignite border border-ignite/20 rounded text-xs
                   font-semibold transition-colors flex items-center gap-1 shrink-0 cursor-pointer">
            ��� Compile
          </button>
          {#if activeTabPath && !activeTabPath.endsWith('.md')}
            <button
              on:click={() => activeArea = 'blueprint'}
              class="px-2.5 py-1 my-1 bg-ink-2 hover:bg-ink-3 hover:text-ignite border border-ink-line rounded text-xs
                     font-semibold transition-colors flex items-center gap-1 shrink-0 cursor-pointer"
              title="Visualize as Blueprint diagram">
              ��� Blueprint
            </button>
          {/if}
          {#if runPanelContract && contracts.some(c => c.name === runPanelContract)}
            <button
              on:click={() => runPanelOpen = !runPanelOpen}
              class="px-2.5 py-1 mr-2 my-1 rounded text-xs font-semibold transition-colors
                     flex items-center gap-1 shrink-0 cursor-pointer border
                     {runPanelOpen
                       ? 'bg-core text-ink border-core'
                       : 'bg-core/15 hover:bg-core/25 text-core border-core/20'}"
              title="Run contract (������)">
              ��� Run
            </button>
          {:else if activeTabPath}
            <button
              on:click={handleLoadFromEditor}
              class="px-2.5 py-1 mr-2 my-1 bg-ink-2 text-core/40 border border-ink-line rounded text-xs
                     font-semibold transition-colors flex items-center gap-1 shrink-0
                     cursor-not-allowed" title="Compile first to enable Run">
              ��� Run
            </button>
          {/if}
        {/if}
      </div>

      <!-- ������ ROW 2: Tool view tabs ������������������������������������������������������������������������������������������������������������������������������������������������ -->
      <div class="flex items-center bg-ink border-b border-ink-line/50 shrink-0 overflow-x-auto">
        <!-- Group label -->
        <span class="text-[9px] font-bold uppercase tracking-[0.15em] text-warm/40 px-2.5 select-none shrink-0 font-mono">
          Tools
        </span>
        <div class="w-px h-3.5 bg-ink-line shrink-0"></div>

        {#each VIEW_TABS as vt}
          {@const isActive = activeArea === vt.id}
          <button
            on:click={() => { activeArea = vt.id }}
            class="relative px-3 py-1.5 text-xs whitespace-nowrap shrink-0 transition-colors cursor-pointer
                   {isActive
                     ? 'text-ignite'
                     : 'text-warm hover:text-warm-3'}">
            {vt.label}
            {#if isActive}
              <span class="absolute bottom-0 left-2 right-2 h-px bg-ignite rounded-full"></span>
            {/if}
          </button>
        {/each}
      </div>

      <!-- ������ MAIN CONTENT ������������������������������������������������������������������������������������������������������������������������������������������������������������ -->
      <div class="flex-1 overflow-hidden relative min-h-0">

        <!-- EDITOR -->
        <div
          class="absolute inset-0 flex flex-col overflow-hidden"
          style="visibility:{activeArea === 'editor' ? 'visible' : 'hidden'};
                 pointer-events:{activeArea === 'editor' ? 'auto' : 'none'}"
        >
          {#if openTabs.length === 0}
            <WelcomeDashboard
              on:tryDemoBlueprint={() => {
                activeArea = 'blueprint'
              }}
              on:newFile={(e) => {
                preselectedTemplateId = e.detail.templateId
                wizardOpen = true
              }}
              on:openDoc={(e) => {
                handleOpenDoc(e.detail.path, e.detail.title)
              }}
            />
          {:else}
            <!-- Breadcrumbs + diagnostics header -->
            <div class="bg-ink-1 border-b border-ink-line shrink-0 text-xs">
              <!-- Row 1: breadcrumbs -->
              {#if breadcrumbs.length > 0}
                <div class="flex items-center px-3 py-1 gap-1 border-b border-ink-line/60 text-[11px] font-mono">
                  {#each breadcrumbs as crumb, i}
                    {#if i > 0}<span class="text-warm/30 select-none">���</span>{/if}
                    <span class="{i === breadcrumbs.length - 1
                      ? 'text-warm-3 font-medium'
                      : 'text-warm hover:text-warm-3 cursor-pointer transition-colors'}">{crumb}</span>
                  {/each}
                </div>
              {/if}

              <!-- Row 2: diagnostics + status -->
              <div class="flex items-center gap-3 px-3 py-1 font-mono">
                {#if errCount > 0}
                  <button class="text-oof hover:text-ember transition-colors cursor-pointer"
                    on:click={() => { bottomOpen = true; bottomTab = 'problems' }}>
                    ��� {errCount} error{errCount > 1 ? 's' : ''}
                  </button>
                {/if}
                {#if warnCount > 0}
                  <button class="text-escape hover:text-ember transition-colors cursor-pointer"
                    on:click={() => { bottomOpen = true; bottomTab = 'problems' }}>
                    ��� {warnCount} warning{warnCount > 1 ? 's' : ''}
                  </button>
                {/if}
                {#if errCount === 0 && warnCount === 0 && activeTabPath && !activeTabPath.endsWith('.md')}
                  <span class="text-core">��� No issues</span>
                {/if}
                {#if !activeTabPath}
                  <span class="text-warm/40 italic">
                    Scratch buffer ��� open a file or press <kbd class="bg-ink-2 rounded px-1 not-italic">���N</kbd>
                  </span>
                {/if}

                <div class="flex-1"></div>

                {#if activeTabPath && !activeTabPath.endsWith('.md') && compileStatus[activeTabPath] === 'compiling'}
                  <span class="text-temporal animate-pulse">��� Compiling���</span>
                {:else if activeTabPath && !activeTabPath.endsWith('.md') && compileStatus[activeTabPath] === 'ok'}
                  <span class="text-core">��� Compiled</span>
                {:else if activeTabPath && !activeTabPath.endsWith('.md') && compileStatus[activeTabPath] === 'error'}
                  <span class="text-oof">��� Compile failed</span>
                {/if}

                {#if isSavingNow}
                  <span class="text-temporal/60">Saving���</span>
                {:else if lastSavedAt}
                  <span class="text-warm/60 font-sans">Saved {formatRelTime(lastSavedAt)}</span>
                {:else if activeTabPath && !activeTabPath.endsWith('.md')}
                  <span class="text-warm/30 text-[10px]">���S to save</span>
                {/if}
              </div>
            </div>
            <div class="flex-1 min-h-0 overflow-hidden relative">


              {#if activeTabPath.endsWith('.md')}
                <DocsView path={activeTabPath} title={activeTabPath.split('/').pop()?.replace(/\.md$/, '').replace(/-/g, ' ') || 'Spec'} />
              {:else}
                <MonacoEditor
                  bind:this={editorRef}
                  value=""
                  filePath={activeTabPath}
                  fontSize={$settings.editor.fontSize}
                  tabSize={$settings.editor.tabSize}
                  wordWrap={$settings.editor.wordWrap}
                  minimap={$settings.editor.minimap}
                  fontFamily={$settings.editor.fontFamily}
                  on:change={() => {
                    if (activeTabPath) {
                      const tab = openTabs.find(t => t.path === activeTabPath)
                      if (tab && !tab.dirty) {
                        openTabs = openTabs.map(t =>
                          t.path === activeTabPath ? { ...t, dirty: true } : t)
                      }
                      if ($settings.workflow?.autoSave) {
                        clearTimeout(autoSaveTimer)
                        autoSaveTimer = setTimeout(() => {
                          const src = editorRef?.getValue() ?? ''
                          handleEditorSave(src)
                        }, $settings.workflow.autoSaveDelay ?? 3000)
                      }
                    }
                  }}
                  on:save={(e) => handleEditorSave(e.detail)}
                  on:goToFile={(e) => handleJumpToLine(e.detail.path, e.detail.line)}
                  on:diagnostics={(e) => {
                    if (activeTabPath) {
                      openTabs = openTabs.map(t =>
                        t.path === activeTabPath ? { ...t, diagnostics: e.detail } : t)
                    }
                  }}
                />
              {/if}
            </div>
          {/if}
        </div>

        <!-- BLUEPRINT -->
        {#if activeArea === 'blueprint'}
          <div class="absolute inset-0">
            <BlueprintView
              content={activeTab?.content ?? (editorRef?.getValue() ?? '')}
              filePath={activeTabPath}
              on:gotoSource={(e) => {
                activeArea = 'editor'
                setTimeout(() => editorRef?.goToLine(e.detail), 50)
              }}
              on:runContract={(e) => {
                runPanelContract = e.detail
                runPanelOpen = true
              }}
            />
          </div>
        {/if}

        <!-- DISPATCH -->
        {#if activeArea === 'dispatch'}
          <div class="absolute inset-0 overflow-auto p-4">
            <DispatchPanel
              {contracts}
              selected={selectedContract}
              initialInputs={replayInputs}
              on:refresh={refresh}
            />
          </div>
        {/if}

        <!-- DAG -->
        {#if activeArea === 'dag'}
          <div class="absolute inset-0 p-4">
            <ContractDAG {contracts} preselected={dagSelectedContract} />
          </div>
        {/if}

        <!-- SYSTEM -->
        {#if activeArea === 'system'}
          <div class="absolute inset-0 overflow-auto p-4">
            <SystemGraph on:drillDown={(e) => handleDrillDown(e.detail)} />
          </div>
        {/if}

        <!-- TRACER -->
        {#if activeArea === 'tracer'}
          <div class="absolute inset-0 overflow-auto p-4">
            <ExecutionTracer {contracts} />
          </div>
        {/if}

        <!-- TIMELINE (main area ��� full canvas with D3 zoom) -->
        {#if activeArea === 'timeline'}
          <div class="absolute inset-0 overflow-auto p-4">
            <TemporalTimeline />
          </div>
        {/if}

        <!-- VIEW PREVIEW -->
        {#if activeArea === 'view_preview'}
          <div class="absolute inset-0 overflow-hidden flex bg-ink">
            <ViewInspector {workspace} />
          </div>
        {/if}

        <!-- SCHEMA FORM -->
        {#if activeArea === 'schema_form'}
          <div class="absolute inset-0 overflow-hidden flex bg-ink">
            <ContractFormGenerator {workspace} />
          </div>
        {/if}

        {#if activeTabPath && !activeTabPath.endsWith('.md')}
          <!-- Inline run panel ��� floats over the active view area -->
          <InlineRunPanel
            contractName={runPanelContract}
            bind:open={runPanelOpen}
            on:close={() => runPanelOpen = false}
            on:ran={(e) => {
              artifacts.addRun({
                contractName: e.detail.contractName,
                ts: Date.now(),
                inputs: e.detail.inputs,
                result: e.detail.result,
                durationMs: e.detail.durationMs,
              })
              log(`Run ${e.detail.contractName} ��� ${e.detail.durationMs}ms`, 'ok')
            }}
          />
        {/if}

      </div>

      <!-- ������ BOTTOM PANEL ������������������������������������������������������������������������������������������������������������������������������������������������������������ -->
      {#if bottomOpen}
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div class="h-1 shrink-0 bg-ink-line hover:bg-ignite cursor-ns-resize transition-colors"
             on:mousedown={startBottomDrag}></div>

        <div class="flex flex-col shrink-0 bg-ink border-t border-ink-line overflow-hidden"
             style="height:{bottomHeight}px">
          <div class="flex items-center border-b border-ink-line bg-ink-1 shrink-0">
            {#each BOTTOM_TABS as bt}
              <button on:click={() => bottomTab = bt.id}
                class="px-3 py-1.5 text-xs whitespace-nowrap transition-colors cursor-pointer
                       {bottomTab === bt.id ? 'text-ignite border-b border-ignite' : 'text-warm hover:text-warm-3'}">
                {bt.label}
                {#if bt.id === 'output' && logErrCount > 0}
                  <span class="ml-1 bg-oof text-ink-1 text-[9px] rounded px-1 font-bold">{logErrCount}</span>
                {/if}
                {#if bt.id === 'problems' && (totalErrCount + totalWarnCount) > 0}
                  <span class="ml-1 {totalErrCount > 0 ? 'bg-oof' : 'bg-escape'} text-ink-1 text-[9px] rounded px-1 font-bold">
                    {totalErrCount + totalWarnCount}
                  </span>
                {/if}
                {#if bt.id === 'artifacts'}
                  {@const total = $buildsStore.length + $runsStore.length}
                  {#if total > 0}<span class="ml-1 text-warm/40 font-bold">({total})</span>{/if}
                {/if}
              </button>
            {/each}
            <button on:click={() => bottomOpen = false}
              class="ml-auto mr-2 text-warm hover:text-warm-3 text-xs cursor-pointer">���</button>
          </div>

          <div class="flex-1 overflow-auto">
            {#if bottomTab === 'output'}
              <div class="p-2 space-y-0.5 text-xs">
                {#if outputLog.length === 0}
                  <div class="text-gray-600 italic py-2">No output yet.</div>
                {:else}
                  {#each outputLog as entry}
                    <div class="flex gap-2 leading-5">
                      <span class="text-gray-700 shrink-0">{entry.ts}</span>
                      <span class="{LOG_COLORS[entry.type]} break-all">{entry.text}</span>
                    </div>
                  {/each}
                  <div bind:this={outputEnd}></div>
                {/if}
              </div>
            {:else if bottomTab === 'problems'}
              <ProblemsPanel
                {openTabs}
                on:jumpTo={(e) => handleJumpToLine(e.detail.path, e.detail.line)}
              />
            {:else if bottomTab === 'observations'}
              <div class="p-2"><ObservationStream /></div>
            {:else if bottomTab === 'facts'}
              <div class="p-2"><FactExplorer /></div>
            {:else if bottomTab === 'artifacts'}
              <BuildArtifacts
                on:replay={(e) => handleReplay(e.detail)}
                on:openArtifact={(e) => handleFileSelected(e.detail)}
              />
            {:else if bottomTab === 'debugger'}
              <DebuggerPanel
                on:replay={(e) => handleReplay(e.detail)}
              />
            {/if}
          </div>
        </div>
      {/if}

    </main>

    <!-- ������ RIGHT PANEL (inspector, drag-resizable) ��������������������������������������������������������������������������������������� -->
    {#if rightPanel}
      <aside
        class="relative shrink-0 bg-ink border-l border-ink-line flex flex-col overflow-hidden"
        style="width: {rightWidth}px"
      >
        <div class="flex items-center justify-between px-2 py-1 border-b border-ink-line shrink-0 bg-ink-1">
          <span class="text-xs font-bold text-warm uppercase tracking-wider font-mono">
            {RIGHT_PANELS.find(p => p.id === rightPanel)?.label ?? rightPanel}
          </span>
          {#if selectedContract}
            <span class="text-xs text-warm/40 truncate max-w-24 ml-1" title={selectedContract}>{selectedContract}</span>
          {/if}
          <button on:click={() => rightPanel = null}
            class="text-warm/50 hover:text-warm-3 text-xs w-4 h-4 flex items-center justify-center cursor-pointer ml-1">���</button>
        </div>

        <div class="flex-1 overflow-hidden min-h-0">
          {#if rightPanel === 'inspector'}
            <ContractInspector
              contractName={selectedContract}
              on:openInDag={(e) => handleInspectorDag(e.detail)}
              on:openDispatch={(e) => handleInspectorDispatch(e.detail)}
            />
          {:else}
            <StructureView
              content={activeTab?.content ?? (editorRef?.getValue() ?? '')}
              filePath={activeTabPath}
              on:goToLine={(e) => { activeArea = 'editor'; setTimeout(() => editorRef?.goToLine(e.detail), 50) }}
            />
          {/if}
        </div>

        <!-- Left edge drag handle -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div class="absolute left-0 top-0 bottom-0 w-1 cursor-col-resize z-10
                    hover:bg-ignite/30 active:bg-ignite/50 transition-colors"
             on:mousedown={startRightDrag}></div>
      </aside>
    {/if}

    <!-- ������ RIGHT ICON STRIP ������������������������������������������������������������������������������������������������������������������������������������������������������������ -->
    <nav class="w-10 shrink-0 bg-ink-1 border-l border-ink-line flex flex-col items-center py-1">
      {#each RIGHT_PANELS as p}
        <button title={p.label} on:click={() => toggleRight(p.id)}
          class="w-8 h-8 flex items-center justify-center rounded text-sm transition-colors cursor-pointer relative
                 {rightPanel === p.id ? 'bg-ignite/15 text-ignite' : 'text-warm hover:text-warm-3 hover:bg-ink-2'}">
          {p.icon}
          {#if rightPanel === p.id}
            <span class="absolute right-0 top-1.5 bottom-1.5 w-0.5 bg-ignite rounded-l"></span>
          {/if}
        </button>
      {/each}
    </nav>

  </div>

  <!-- ������ STATUS BAR ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������ -->
  <footer class="h-6 bg-ink-1 border-t border-ink-line flex items-center px-2 gap-3 text-xs shrink-0 select-none">
    <IgMark variant="oval" class="w-3.5 h-3.5" />
    <span class="text-warm-3 font-semibold font-mono">Igniter</span>
    <span class="text-warm/40">���</span>
    <span class="text-ember font-mono">{status.backend}</span>
    <span class="text-warm/30">|</span>
    <span class="text-warm-2/70 font-mono">{status.facts_count} facts</span>
    <span class="text-warm-2/70 font-mono">{status.contracts_count} contracts</span>
    <span class="text-warm-2/70 font-mono">{status.observations_count} obs</span>
    {#if totalErrCount > 0}
      <button class="text-oof ml-1 hover:text-ember transition-colors cursor-pointer"
        on:click={() => { bottomOpen = true; bottomTab = 'problems' }}>
        ��� {totalErrCount}
      </button>
    {/if}
    {#if totalWarnCount > 0}
      <button class="text-escape hover:text-ember transition-colors cursor-pointer"
        on:click={() => { bottomOpen = true; bottomTab = 'problems' }}>
        ��� {totalWarnCount}
      </button>
    {/if}

    <div class="flex-1"></div>

    {#if openTabs.length > 1}
      <span class="text-warm/50 font-mono">{openTabs.length} files</span>
    {/if}

    {#if activeTabPath}
      <span class="text-warm/60 font-mono truncate max-w-64" title={activeTabPath}>
        {activeTabPath.split('/').slice(-2).join('/')}
      </span>
    {/if}

    <!-- Palette shortcut hint -->
    <span class="text-warm/30 hidden sm:inline font-mono">���K</span>

    <button
      on:click={() => { bottomOpen = !bottomOpen; if (bottomOpen) bottomTab = 'output' }}
      class="text-warm/60 hover:text-warm-3 flex items-center gap-1 transition-colors cursor-pointer font-mono"
      title="Toggle tool windows">
      {bottomOpen ? '���' : '���'} {BOTTOM_TABS.find(t => t.id === bottomTab)?.label ?? 'Output'}
    </button>
  </footer>
</div>
