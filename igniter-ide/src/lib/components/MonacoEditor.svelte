<script lang="ts">
  import { onMount, onDestroy, createEventDispatcher } from 'svelte'
  import { api } from '$lib/api'
  import type { DiagnosticInfo } from '$lib/types'

  export let value: string = ''
  export let filePath: string = ''
  export let contractName: string = 'Contract'
  export let readonly: boolean = false
  export let fontSize: number = 13
  export let tabSize: number = 2
  export let wordWrap: 'on' | 'off' = 'on'
  export let minimap: boolean = false
  export let fontFamily: string = 'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace'

  const dispatch = createEventDispatcher<{
    change: void
    save: string
    diagnostics: DiagnosticInfo[]
    goToFile: { path: string; line: number }
  }>()

  let container: HTMLDivElement
  let editor: any
  let monacoLib: any
  let debounceTimer: ReturnType<typeof setTimeout>
  let isDirty = false
  let pendingValue: string | null = null  // queued setValue before editor ready
  let resizeObserver: ResizeObserver | null = null
  let diagSeq = 0   // cancellation token for in-flight check_source calls

  // ������ Workspace intelligence index ���������������������������������������������������������������������������������������������������������������������������������������
  // Shared mutable object ��� all Monaco providers read from it via closure.
  const _hints = {
    contracts:     [] as string[],
    nodes:         [] as string[],
    contractFiles: {} as Record<string, string>,  // contractName ��� absolute path
    contractIr:    {} as Record<string, any>,      // contractName ��� IR JSON
  }

  // ������ Keyword documentation ������������������������������������������������������������������������������������������������������������������������������������������������������������
  const KW_DOCS: Record<string, string> = {
    contract:  'Declares an Igniter contract with typed input ports, compute nodes, and output ports.',
    input:     'Declares an **input port** ��� required at dispatch time.',
    compute:   'Declares a **compute node** with optional dependencies (`with:`) and a callable (`call:`).',
    output:    'Declares an **output port** ��� the contract result value.',
    def:       'Defines a **pure function** reusable within the contract.',
    module:    'Sets the **module namespace** for the file.',
    import:    'Imports definitions from another module.',
    loop:      'Bounded iteration with a `max_steps:` fuel limit.',
    invariant: 'Asserts a compile-time or runtime property of the graph.',
    snapshot:  'Captures a time-indexed snapshot of a node value.',
    read:      'Reads from a **TBackend** store with a lifecycle policy.',
    window:    'Sliding time window over event observations.',
    stream:    'Declares an event stream node.',
    escape:    'Escape hatch for imperative side effects.',
  }

  // ������ Parse node declarations from source text (fast, no IR needed) ���������������������������������
  interface NodeDef { kind: string; type?: string; line: number }

  function parseNodeDefs(text: string): Record<string, NodeDef> {
    const defs: Record<string, NodeDef> = {}
    text.split('\n').forEach((line, i) => {
      const m = line.match(/^\s*(input|compute|output)\s+(\w+)(?:\s*:\s*([\w\[\]<>,\s]+))?/)
      if (m) defs[m[2]] = { kind: m[1], type: m[3]?.trim(), line: i + 1 }
    })
    return defs
  }

  function registerIgniterLanguage(monaco: any) {
    if (monaco.languages.getLanguages().some((l: any) => l.id === 'igniter')) return

    monaco.languages.register({ id: 'igniter', extensions: ['.ig'], aliases: ['Igniter', 'igniter'] })

    monaco.languages.setMonarchTokensProvider('igniter', {
      keywords: [
        'module','import','contract','def','type','trait','impl',
        'input','output','compute','read','snapshot','window','escape',
        'stream','fold_stream','assumptions','olap_point','if','else',
        'let','loop','service','pipeline','step','pure','observed',
        'effect','privileged','irreversible','from','lifecycle',
        'scoped_by','cardinality','max_steps','decreases','fuel',
        'evidence','invariant','predicate','severity','uses','in',
        'emit','clock','every','as_of'
      ],
      typeKeywords: [
        'Integer','Float','String','Bool','Decimal','Collection',
        'Array','Option','History','BiHistory','OLAPPoint','DateTime','Nil','ClockTick'
      ],
      boolKeywords: ['true','false'],
      operators: ['=','+','-','*','/','==','!=','<','>','<=','>=','&&','||','!','++','->','..'],
      tokenizer: {
        root: [
          [/--.*$/, 'comment'],
          [/"[^"]*"/, 'string'],
          [/:[a-zA-Z_]\w*/, 'attribute.value'],
          [/\d+\.\d*/, 'number.float'],
          [/\d+/, 'number'],
          [/[A-Z][a-zA-Z0-9_]*(\[[^\]]*\])?/, 'type.identifier'],
          [/[a-z_$][a-zA-Z0-9_$]*/, {
            cases: {
              '@keywords': 'keyword',
              '@typeKeywords': 'type.identifier',
              '@boolKeywords': 'number',
              '@default': 'identifier'
            }
          }],
          [/[{}()\[\]]/, '@brackets'],
          [/[<>]/, '@brackets'],
          [/[,.:;@]/, 'delimiter'],
        ]
      }
    })

    monaco.editor.defineTheme('igniter-dark', {
      base: 'vs-dark',
      inherit: true,
      rules: [
        { token: 'keyword',          foreground: 'ff6a3d', fontStyle: 'bold' },
        { token: 'type.identifier',  foreground: 'f0a868' },
        { token: 'number',           foreground: 'ffb07a' },
        { token: 'number.float',     foreground: 'ffb07a' },
        { token: 'string',           foreground: '8fbf8a' },
        { token: 'attribute.value',  foreground: '5ec8d8' },
        { token: 'identifier',       foreground: 'e7ddd2' },
        { token: 'delimiter',        foreground: '9a8a7c' },
        { token: 'comment',          foreground: '6f6256', fontStyle: 'italic' },
      ],
      colors: {
        'editor.background':              '#1a1510',  // ink-1
        'editor.foreground':              '#e7ddd2',
        'editor.lineHighlightBackground': '#221b15',  // ink-2
        'editor.selectionBackground':     '#ff6a3d33',
        'editorCursor.foreground':        '#ff6a3d',  // ignition
        'editorLineNumber.foreground':    '#4d4035',
        'editorBracketMatch.border':      '#f0a868',
        'editorLineNumber.activeForeground': '#e7ddd2',
        'editorIndentGuide.background1':  '#2b221b',  // line
        'scrollbar.shadow':               '#00000000',
        'scrollbarSlider.background':     '#3a2f26',
        'scrollbarSlider.hoverBackground':'#4d4035',
      }
    })

    monaco.editor.defineTheme('igniter-paper', {
      base: 'vs-light',
      inherit: true,
      rules: [
        { token: 'keyword',          foreground: 'cf4517', fontStyle: 'bold' },
        { token: 'type.identifier',  foreground: 'a96b2c' },
        { token: 'number',           foreground: 'bf5a28' },
        { token: 'number.float',     foreground: 'bf5a28' },
        { token: 'string',           foreground: '4f8a52' },
        { token: 'attribute.value',  foreground: '1f7d8c' },
        { token: 'identifier',       foreground: '2a2018' },
        { token: 'delimiter',        foreground: '8a7964' },
        { token: 'comment',          foreground: '9a8576', fontStyle: 'italic' },
      ],
      colors: {
        'editor.background':              '#f5f1ea',  // paper
        'editor.foreground':              '#2a2018',  // paper-ink
        'editor.lineHighlightBackground': '#ece5da',
        'editor.selectionBackground':     '#cf451733',
        'editorCursor.foreground':        '#cf4517',
        'editorLineNumber.foreground':    '#c4b09a',
        'editorBracketMatch.border':      '#a96b2c',
        'editorLineNumber.activeForeground': '#2a2018',
        'editorIndentGuide.background1':  '#e0d6c8',
        'scrollbar.shadow':               '#00000000',
        'scrollbarSlider.background':     '#ece5da',
        'scrollbarSlider.hoverBackground':'#c4b09a',
      }
    })

    // Static completion items built once ��� keywords and snippets never change.
    // Range is adjusted per-request; items object is reused to avoid GC churn.
    const KEYWORDS = ['contract','def','input','output','compute','read','loop',
                      'invariant','snapshot','window','module','import']
    const SNIPPETS = [
      { label: 'contract', insertText: 'contract ${1:Name} {\n  input ${2:name}: ${3:String}\n  \n  output ${4:result}: ${5:String}\n}', documentation: 'New contract' },
      { label: 'def',      insertText: 'def ${1:name}(${2:param}: ${3:Integer}) -> ${4:Integer} {\n  $0\n}', documentation: 'Function definition' },
      { label: 'loop',     insertText: 'loop ${1:Name} in ${2:collection} max_steps: ${3:100} {\n  compute ${4:result} = $0\n}', documentation: 'Bounded loop' },
      { label: 'read',     insertText: 'read ${1:name}: ${2:Collection[T]} from TBackend lifecycle: :${3|local,session,window,durable|}', documentation: 'TBackend read' },
      { label: 'invariant',insertText: 'invariant ${1:name} predicate: ${2:pred} severity: :${3|error,warn,soft,metric|}', documentation: 'Invariant' },
    ]

    monaco.languages.registerCompletionItemProvider('igniter', {
      provideCompletionItems: (model: any, position: any) => {
        const word  = model.getWordUntilPosition(position)
        const range = {
          startLineNumber: position.lineNumber, endLineNumber: position.lineNumber,
          startColumn: word.startColumn,        endColumn:   word.endColumn,
        }
        // Reuse pre-built arrays; only set range per invocation
        const kwItems   = KEYWORDS.map(kw => ({ label: kw, kind: monaco.languages.CompletionItemKind.Keyword, insertText: kw, range }))
        const snipItems = SNIPPETS.map(s  => ({
          label: s.label, kind: monaco.languages.CompletionItemKind.Snippet,
          insertText: s.insertText, insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet,
          documentation: s.documentation, range,
        }))
        // Dynamic workspace hints ��� small arrays, cheap
        const contractItems = _hints.contracts.map(n => ({ label: n, kind: monaco.languages.CompletionItemKind.Class,  insertText: n, range, detail: 'Contract' }))
        const nodeItems     = _hints.nodes    .map(n => ({ label: n, kind: monaco.languages.CompletionItemKind.Field,   insertText: n, range, detail: 'Node'     }))
        return { suggestions: [...kwItems, ...snipItems, ...contractItems, ...nodeItems] }
      }
    })

    // ������ Hover provider ������������������������������������������������������������������������������������������������������������������������������������������������������������������������
    monaco.languages.registerHoverProvider('igniter', {
      provideHover: (model: any, position: any) => {
        const word = model.getWordAtPosition(position)?.word
        if (!word) return null

        // 1. Keyword
        if (KW_DOCS[word]) {
          return {
            contents: [
              { value: `**\`${word}\`** �� *keyword*` },
              { value: KW_DOCS[word] },
            ]
          }
        }

        // 2. Contract from workspace index
        const ir = _hints.contractIr[word]
        if (ir) {
          const fc   = ir.fragment_class ?? ir.modifier ?? '���'
          const ins  = (ir.input_ports  ?? ir.inputs  ?? [])
            .map((p: any) => `\`${p.name}: ${p.type_tag ?? p.type?.name ?? '?'}\``).join('  ')
          const outs = (ir.output_ports ?? ir.outputs ?? [])
            .map((p: any) => `\`${p.name}: ${p.type_tag ?? p.type?.name ?? '?'}\``).join('  ')
          const lines: string[] = [
            `**${word}** �� Contract`,
            `*${fc}*`,
          ]
          if (ins)  lines.push(`**Inputs:** ${ins}`)
          if (outs) lines.push(`**Outputs:** ${outs}`)
          if (_hints.contractFiles[word]) lines.push(`*${_hints.contractFiles[word].split('/').slice(-2).join('/')}*`)
          return { contents: lines.map(value => ({ value })) }
        }

        // 3. Node declared in current file
        const defs = parseNodeDefs(model.getValue())
        if (defs[word]) {
          const { kind, type } = defs[word]
          const kindColor: Record<string, string> = { input: '����', compute: '������', output: '����' }
          const lines: string[] = [`${kindColor[kind] ?? '��'} **${word}** �� \`${kind}\``]
          if (type) lines.push(`Type: \`${type}\``)
          return { contents: lines.map(value => ({ value })) }
        }

        return null
      }
    })

    // ������ Definition provider (intra-file) ������������������������������������������������������������������������������������������������������������������
    monaco.languages.registerDefinitionProvider('igniter', {
      provideDefinition: (model: any, position: any) => {
        const word = model.getWordAtPosition(position)?.word
        if (!word) return null
        const defs = parseNodeDefs(model.getValue())
        const d = defs[word]
        if (d) {
          return [{
            uri: model.uri,
            range: {
              startLineNumber: d.line, endLineNumber: d.line,
              startColumn: 1,         endColumn: 200,
            }
          }]
        }
        return null
      }
    })

    // ������ Code Action (Quick Fix) provider ������������������������������������������������������������������������������������������������������������������
    monaco.languages.registerCodeActionProvider('igniter', {
      provideCodeActions: (model: any, _range: any, context: any) => {
        const actions: any[] = []
        for (const diag of (context.markers ?? [])) {
          const msg = diag.message ?? ''

          // "Add missing input" for undefined-node-style errors
          const undefinedMatch = msg.match(/undefined|unknown|not found[:\s]+['"`]?(\w+)['"`]?/i)
          if (undefinedMatch) {
            const nodeName = undefinedMatch[1]
            const insertLine = 1
            actions.push({
              title: `Add \`input ${nodeName}\` declaration`,
              kind: 'quickfix',
              diagnostics: [diag],
              edit: {
                edits: [{
                  resource: model.uri,
                  textEdit: {
                    range: { startLineNumber: insertLine, endLineNumber: insertLine, startColumn: 1, endColumn: 1 },
                    text: `  input ${nodeName}: String\n`,
                  }
                }]
              },
              isPreferred: true,
            })
          }

          // Generic: "Show in Problems" ��� opens the Problems panel via a marker action
          actions.push({
            title: `Show all problems`,
            kind: 'quickfix',
            diagnostics: [diag],
            command: { id: 'igniter.showProblems', title: 'Show Problems' },
          })
        }
        return { actions, dispose: () => {} }
      }
    })
  }

  async function runDiagnostics(source: string) {
    const seq = ++diagSeq   // bump sequence; stale responses will be ignored
    const name = contractName || filePath.split('/').pop()?.replace('.ig','') || 'Contract'
    try {
      const diags = await api.checkSource(source, name)
      if (seq !== diagSeq) return   // superseded by a newer call
      dispatch('diagnostics', diags)
      if (editor && monacoLib) {
        const model = editor.getModel()
        if (model) {
          monacoLib.editor.setModelMarkers(model, 'igniter', diags.map(d => ({
            startLineNumber: d.line ?? 1,
            startColumn: d.col ?? 1,
            endLineNumber: d.line ?? 1,
            endColumn: (d.col ?? 1) + 12,
            message: `${d.rule}: ${d.message}`,
            severity: d.severity === 'error'
              ? monacoLib.MarkerSeverity.Error
              : d.severity === 'warning'
              ? monacoLib.MarkerSeverity.Warning
              : monacoLib.MarkerSeverity.Info,
          })))
        }
      }
    } catch (_) {}
  }

  onMount(async () => {
    const monaco = await import('monaco-editor')
    monacoLib = monaco

    try {
      registerIgniterLanguage(monaco)
    } catch (e) {
      console.warn('Igniter language registration failed:', e)
    }

    editor = monaco.editor.create(container, {
      value,
      language: 'igniter',
      theme: 'igniter-dark',
      readOnly: readonly,
      fontSize,
      fontFamily,
      minimap: { enabled: minimap },
      lineNumbers: 'on',
      renderLineHighlight: 'all',
      scrollBeyondLastLine: false,
      automaticLayout: false,  // managed manually via ResizeObserver
      tabSize,
      insertSpaces: true,
      wordWrap,
      folding: true,
      bracketPairColorization: { enabled: true },
      suggest: { showSnippets: true },
      padding: { top: 8, bottom: 8 },
    })

    editor.onDidChangeModelContent(() => {
      // Guard: only trigger Svelte reactivity on first change after last save.
      // Calling isDirty = true unconditionally re-renders this component on
      // every single keystroke even when the value is already true.
      if (!isDirty) isDirty = true

      // Do NOT call editor.getValue() here ��� serializing the entire document
      // to a string on every keystroke creates GC pressure and causes freezes.
      // Instead, dispatch a void notification; consumers read the value lazily.
      dispatch('change')

      // Debounce diagnostics ��� cancellation via diagSeq prevents stale
      // check_source responses from overwriting newer results.
      clearTimeout(debounceTimer)
      debounceTimer = setTimeout(() => runDiagnostics(editor.getValue()), 1500)
    })

    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => {
      isDirty = false
      dispatch('save', editor.getValue())
    })

    // ������ ���Click ��� cross-file Go to Definition ������������������������������������������������������������������������������������������������������
    editor.onMouseDown((e: any) => {
      if (!(e.event.metaKey || e.event.ctrlKey)) return
      if (e.target.type !== monaco.editor.MouseTargetType.CONTENT_TEXT) return
      const pos  = e.target.position
      if (!pos) return
      const word = editor.getModel()?.getWordAtPosition(pos)?.word
      if (!word) return
      const filePath = _hints.contractFiles[word]
      if (filePath) dispatch('goToFile', { path: filePath, line: 1 })
    })

    // ������ Custom command: "Show Problems" ���������������������������������������������������������������������������������������������������������������������
    editor.addCommand(0, () => {}, 'igniter.showProblems')  // placeholder; parent handles via goToFile

    // Manual resize observer ��� avoids Monaco's built-in rAF polling
    resizeObserver = new ResizeObserver(() => { editor?.layout() })
    resizeObserver.observe(container)

    // Apply any value set before editor was ready
    if (pendingValue !== null) {
      editor.setValue(pendingValue)
      pendingValue = null
    }

    // Initial diagnostics
    const initialValue = editor.getValue()
    if (initialValue) setTimeout(() => runDiagnostics(initialValue), 400)
  })

  // Reactively apply settings changes to the live editor
  $: if (editor) {
    editor.updateOptions({ fontSize, tabSize, wordWrap, minimap: { enabled: minimap }, fontFamily })
  }

  onDestroy(() => {
    clearTimeout(debounceTimer)
    resizeObserver?.disconnect()
    editor?.dispose()
  })

  export function getValue(): string { return editor?.getValue() ?? '' }
  export function setValue(v: string) {
    if (editor) {
      if (v !== editor.getValue()) {
        editor.setValue(v)
        isDirty = false   // loading a file resets dirty state
      }
    } else {
      pendingValue = v  // apply once editor finishes loading
    }
  }
  export function focus() { editor?.focus() }
  export function layout() { editor?.layout() }
  export function insertText(code: string) {
    if (!editor) return
    const sel = editor.getSelection()
    editor.executeEdits('ai-insert', [{ range: sel, text: code, forceMoveMarkers: true }])
    editor.focus()
  }

  export function goToLine(line: number) {
    if (!editor) return
    editor.revealLineInCenter(line)
    editor.setPosition({ lineNumber: line, column: 1 })
    editor.focus()
  }
  export function setWorkspaceIndex(
    contracts: string[],
    nodes: string[] = [],
    contractFiles: Record<string, string> = {},
    contractIr: Record<string, any> = {}
  ) {
    _hints.contracts = contracts
    _hints.nodes     = nodes
    Object.assign(_hints.contractFiles, contractFiles)
    Object.assign(_hints.contractIr,    contractIr)
  }

  export function updateContractIr(name: string, ir: any) {
    _hints.contractIr[name] = ir
    if (!_hints.contracts.includes(name)) _hints.contracts = [..._hints.contracts, name]
  }
</script>

<div class="relative w-full h-full flex flex-col">
  {#if filePath}
    <div class="flex items-center gap-2 px-3 py-1 bg-ink-2 border-b border-ink-line text-xs text-warm">
      <span class="text-ignite">����</span>
      <span class="truncate">{filePath.split('/').pop()}</span>
      {#if isDirty}<span class="text-ember ml-1">���</span>{/if}
      <span class="ml-auto opacity-40">Ctrl+S to save</span>
    </div>
  {/if}
  <div bind:this={container} class="flex-1 w-full" style="min-height: 400px"></div>
</div>
