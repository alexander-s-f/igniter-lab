<script lang="ts">
  import { settings, DEFAULTS } from '$lib/stores/settings'
  import type { IdeSettings } from '$lib/types'

  // Local copy for editing; synced to store on every change
  let s: IdeSettings = JSON.parse(JSON.stringify($settings))

  function save() {
    settings.set(JSON.parse(JSON.stringify(s)))
  }

  function reset() {
    settings.reset()
    s = JSON.parse(JSON.stringify(DEFAULTS))
  }

  let showApiKey = false

  const ACCENT_COLORS: Array<{ id: IdeSettings['appearance']['accentColor']; label: string; cls: string }> = [
    { id: 'blue',   label: 'Blue',   cls: 'bg-blue-500' },
    { id: 'purple', label: 'Purple', cls: 'bg-purple-500' },
    { id: 'green',  label: 'Green',  cls: 'bg-emerald-500' },
    { id: 'cyan',   label: 'Cyan',   cls: 'bg-cyan-500' },
  ]

  const AI_PROVIDERS = [
    { id: 'anthropic', label: 'Anthropic', models: ['claude-sonnet-4-6', 'claude-opus-4-8', 'claude-haiku-4-5-20251001'] },
    { id: 'openai',    label: 'OpenAI',    models: ['gpt-4o', 'gpt-4o-mini', 'gpt-4-turbo'] },
    { id: 'ollama',    label: 'Ollama',    models: ['llama3.2', 'mistral', 'codestral', 'qwen2.5-coder'] },
  ]

  $: currentProvider = AI_PROVIDERS.find(p => p.id === s.ai.provider) ?? AI_PROVIDERS[0]

  const FONT_FAMILIES = [
    { label: 'System Mono',    value: 'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace' },
    { label: 'JetBrains Mono', value: '"JetBrains Mono", monospace' },
    { label: 'Fira Code',      value: '"Fira Code", monospace' },
    { label: 'Cascadia Code',  value: '"Cascadia Code", monospace' },
  ]
</script>

<div class="max-w-2xl mx-auto space-y-6 pb-8">
  <div class="flex items-center justify-between">
    <h2 class="text-sm font-bold text-gray-300">IDE Settings</h2>
    <button
      on:click={reset}
      class="text-xs text-gray-600 hover:text-gray-400 transition-colors">
      Reset to defaults
    </button>
  </div>

  <!-- ������ Editor ��������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������� -->
  <section class="bg-gray-900 border border-gray-800 rounded-lg p-4 space-y-4">
    <h3 class="text-xs font-bold text-gray-400 uppercase tracking-wider">Editor</h3>

    <div class="grid grid-cols-2 gap-4">
      <!-- Font Size -->
      <div>
        <label class="block text-xs text-gray-400 mb-1.5">Font Size <span class="text-gray-500">{s.editor.fontSize}px</span></label>
        <input
          type="range" min="11" max="20" step="1"
          bind:value={s.editor.fontSize}
          on:input={save}
          class="w-full accent-blue-500 cursor-pointer"
        />
        <div class="flex justify-between text-xs text-gray-700 mt-0.5">
          <span>11</span><span>20</span>
        </div>
      </div>

      <!-- Tab Size -->
      <div>
        <label class="block text-xs text-gray-400 mb-1.5">Tab Size</label>
        <div class="flex gap-2">
          {#each [2, 4] as size}
            <label class="flex items-center gap-1.5 cursor-pointer">
              <input
                type="radio"
                bind:group={s.editor.tabSize}
                value={size}
                on:change={save}
                class="accent-blue-500"
              />
              <span class="text-sm text-gray-300">{size}</span>
            </label>
          {/each}
        </div>
      </div>

      <!-- Word Wrap -->
      <div>
        <label class="block text-xs text-gray-400 mb-1.5">Word Wrap</label>
        <label class="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            checked={s.editor.wordWrap === 'on'}
            on:change={(e) => { s.editor.wordWrap = (e.target as HTMLInputElement).checked ? 'on' : 'off'; save() }}
            class="accent-blue-500 w-4 h-4"
          />
          <span class="text-sm text-gray-300">Enabled</span>
        </label>
      </div>

      <!-- Minimap -->
      <div>
        <label class="block text-xs text-gray-400 mb-1.5">Minimap</label>
        <label class="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            bind:checked={s.editor.minimap}
            on:change={save}
            class="accent-blue-500 w-4 h-4"
          />
          <span class="text-sm text-gray-300">Show minimap</span>
        </label>
      </div>
    </div>

    <!-- Font Family -->
    <div>
      <label class="block text-xs text-gray-400 mb-1.5">Font Family</label>
      <div class="flex flex-wrap gap-2">
        {#each FONT_FAMILIES as ff}
          <button
            on:click={() => { s.editor.fontFamily = ff.value; save() }}
            class="px-2.5 py-1 rounded text-xs transition-colors
                   {s.editor.fontFamily === ff.value
                     ? 'bg-blue-700 text-white'
                     : 'bg-gray-800 text-gray-400 hover:bg-gray-700'}"
            style="font-family: {ff.value}">
            {ff.label}
          </button>
        {/each}
      </div>
    </div>
  </section>

  <!-- ������ Appearance ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������ -->
  <section class="bg-gray-900 border border-gray-800 rounded-lg p-4 space-y-4">
    <h3 class="text-xs font-bold text-gray-400 uppercase tracking-wider">Appearance</h3>

    <div>
      <label class="block text-xs text-gray-400 mb-2">Accent Color</label>
      <div class="flex gap-3">
        {#each ACCENT_COLORS as color}
          <button
            on:click={() => { s.appearance.accentColor = color.id; save() }}
            class="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs transition-colors
                   {s.appearance.accentColor === color.id
                     ? 'bg-gray-700 ring-1 ring-gray-500 text-white'
                     : 'bg-gray-800 text-gray-400 hover:bg-gray-750'}"
          >
            <span class="w-3 h-3 rounded-full {color.cls}"></span>
            {color.label}
          </button>
        {/each}
      </div>
    </div>
  </section>

  <!-- ������ AI Provider ��������������������������������������������������������������������������������������������������������������������������������������������������������������������������������� -->
  <section class="bg-gray-900 border border-gray-800 rounded-lg p-4 space-y-4">
    <h3 class="text-xs font-bold text-gray-400 uppercase tracking-wider">AI Provider</h3>

    <div class="grid grid-cols-2 gap-4">
      <!-- Provider -->
      <div>
        <label class="block text-xs text-gray-400 mb-1.5">Provider</label>
        <select
          bind:value={s.ai.provider}
          on:change={save}
          class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1.5 text-sm text-gray-200 outline-none focus:border-blue-500">
          {#each AI_PROVIDERS as p}
            <option value={p.id}>{p.label}</option>
          {/each}
        </select>
      </div>

      <!-- Model -->
      <div>
        <label class="block text-xs text-gray-400 mb-1.5">Model</label>
        <div class="flex gap-1">
          <input
            bind:value={s.ai.model}
            on:input={save}
            placeholder="model name"
            list="model-suggestions"
            class="flex-1 bg-gray-800 border border-gray-700 rounded px-2 py-1.5 text-sm text-gray-200 outline-none focus:border-blue-500 min-w-0"
          />
          <datalist id="model-suggestions">
            {#each currentProvider.models as m}
              <option value={m}>{m}</option>
            {/each}
          </datalist>
        </div>
        <div class="flex gap-1 flex-wrap mt-1.5">
          {#each currentProvider.models as m}
            <button
              on:click={() => { s.ai.model = m; save() }}
              class="text-xs px-1.5 py-0.5 rounded transition-colors
                     {s.ai.model === m ? 'bg-blue-700 text-white' : 'bg-gray-800 text-gray-500 hover:text-gray-300'}">
              {m.split('-').slice(-2).join('-')}
            </button>
          {/each}
        </div>
      </div>
    </div>

    <!-- API Key -->
    <div>
      <label class="block text-xs text-gray-400 mb-1.5">
        API Key
        {#if s.ai.provider === 'ollama'}
          <span class="text-gray-600 ml-1">(not required for Ollama)</span>
        {/if}
      </label>
      <div class="flex gap-2">
        <input
          type={showApiKey ? 'text' : 'password'}
          bind:value={s.ai.apiKey}
          on:input={save}
          placeholder={s.ai.provider === 'ollama' ? 'n/a' : 'sk-...'}
          disabled={s.ai.provider === 'ollama'}
          class="flex-1 bg-gray-800 border border-gray-700 rounded px-2 py-1.5 text-sm text-gray-200
                 outline-none focus:border-blue-500 disabled:opacity-40 font-mono"
        />
        <button
          on:click={() => showApiKey = !showApiKey}
          disabled={s.ai.provider === 'ollama'}
          class="px-2 py-1.5 bg-gray-800 border border-gray-700 rounded text-xs text-gray-400
                 hover:text-gray-200 hover:bg-gray-700 transition-colors disabled:opacity-40">
          {showApiKey ? 'Hide' : 'Show'}
        </button>
      </div>
      {#if s.ai.apiKey}
        <div class="text-xs text-green-600 mt-1">��� Key configured</div>
      {/if}
    </div>

    <!-- Base URL (Ollama only) -->
    {#if s.ai.provider === 'ollama'}
      <div>
        <label class="block text-xs text-gray-400 mb-1.5">Base URL</label>
        <input
          bind:value={s.ai.baseUrl}
          on:input={save}
          placeholder="http://localhost:11434"
          class="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1.5 text-sm text-gray-200
                 outline-none focus:border-blue-500 font-mono"
        />
      </div>
    {/if}

    <div class="text-xs text-gray-600 bg-gray-800 rounded p-2 leading-relaxed">
      Settings are stored locally in this browser session. API keys never leave your machine.
    </div>
  </section>

  <!-- ������ Workflow ��������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������� -->
  <section class="bg-gray-900 border border-gray-800 rounded-lg p-4 space-y-4">
    <h3 class="text-xs font-bold text-gray-400 uppercase tracking-wider">Workflow</h3>

    <div class="grid grid-cols-2 gap-4">
      <!-- Auto Save -->
      <div>
        <label class="block text-xs text-gray-400 mb-1.5">Auto Save</label>
        <label class="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            bind:checked={s.workflow.autoSave}
            on:change={save}
            class="accent-blue-500 w-4 h-4"
          />
          <span class="text-sm text-gray-300">Save on idle</span>
        </label>
        {#if s.workflow.autoSave}
          <div class="mt-2">
            <label class="block text-xs text-gray-500 mb-1">Delay: {s.workflow.autoSaveDelay}ms</label>
            <input
              type="range" min="500" max="5000" step="500"
              bind:value={s.workflow.autoSaveDelay}
              on:input={save}
              class="w-full accent-blue-500 cursor-pointer"
            />
            <div class="flex justify-between text-xs text-gray-700 mt-0.5">
              <span>0.5s</span><span>5s</span>
            </div>
          </div>
        {/if}
      </div>

      <!-- Auto Compile -->
      <div>
        <label class="block text-xs text-gray-400 mb-1.5">Auto Compile</label>
        <label class="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            bind:checked={s.workflow.autoCompile}
            on:change={save}
            class="accent-blue-500 w-4 h-4"
          />
          <span class="text-sm text-gray-300">Compile on save</span>
        </label>
      </div>

      <!-- Auto Snapshot -->
      <div>
        <label class="block text-xs text-gray-400 mb-1.5">Auto Snapshot</label>
        <label class="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            bind:checked={s.workflow.autoSnapshot}
            on:change={save}
            class="accent-blue-500 w-4 h-4"
          />
          <span class="text-sm text-gray-300">Snapshot on compile</span>
        </label>
      </div>
    </div>

    <div class="text-xs text-gray-600 bg-gray-800 rounded p-2 leading-relaxed space-y-0.5">
      <div><kbd class="bg-gray-700 px-1 rounded">���B</kbd> ��� toggle sidebar</div>
      <div><kbd class="bg-gray-700 px-1 rounded">���J</kbd> ��� toggle bottom panel</div>
      <div><kbd class="bg-gray-700 px-1 rounded">������M</kbd> ��� open Problems</div>
      <div><kbd class="bg-gray-700 px-1 rounded">���K</kbd> ��� command palette</div>
    </div>
  </section>

  <!-- ������ About ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������ -->
  <section class="bg-gray-900 border border-gray-800 rounded-lg p-4 space-y-2">
    <h3 class="text-xs font-bold text-gray-400 uppercase tracking-wider">About</h3>
    <div class="text-xs text-gray-500 space-y-1">
      <div class="flex gap-4">
        <span class="text-gray-600">App</span>
        <span>Igniter IDE</span>
      </div>
      <div class="flex gap-4">
        <span class="text-gray-600">Version</span>
        <span>0.1.0-dev</span>
      </div>
      <div class="flex gap-4">
        <span class="text-gray-600">Runtime</span>
        <span>Tauri v2 + SvelteKit</span>
      </div>
      <div class="flex gap-4">
        <span class="text-gray-600">Engine</span>
        <span>Igniter Machine (Rust)</span>
      </div>
    </div>
  </section>
</div>
