<script lang="ts">
  import { createEventDispatcher } from 'svelte'
  import { api } from '$lib/api'

  export let open = false
  export let workspaceDir: string = ''
  export let currentFilePath: string = ''

  const dispatch = createEventDispatcher<{
    created: string
    close: void
  }>()

  interface Template {
    id: string
    label: string
    icon: string
    description: string
    generate: (name: string, module: string) => string
  }

  const TEMPLATES: Template[] = [
    {
      id: 'empty',
      label: 'Empty Contract',
      icon: '���',
      description: 'Minimal contract ��� one input, one output',
      generate: (name, mod) => `module ${mod}

contract ${name} {
  input data: String

  compute result = data

  output result: String
}
`,
    },
    {
      id: 'transform',
      label: 'Transform',
      icon: '���',
      description: 'Multi-step data transformation',
      generate: (name, mod) => `module ${mod}

type InputData {
  value: String
}

type StepResult {
  value: String
}

type FinalResult {
  result: String
}

def step_one(data: InputData) -> StepResult {
  { value: data.value }
}

def step_two(step: StepResult) -> FinalResult {
  { result: step.value }
}

contract ${name} {
  input data: InputData

  compute step_a = step_one(data)
  compute step_b = step_two(step_a)

  output step_b: FinalResult
}
`,
    },
    {
      id: 'pipeline',
      label: 'Pipeline',
      icon: '���',
      description: 'Typed step-by-step pipeline',
      generate: (name, mod) => `module ${mod}

-- Step functions are declared or imported. Here we import them.
import ${mod}.Steps.{
  validate_input,
  enrich_data,
  produce_output
}

type PipelineInput {
  value: String
}

type PipelineOutput {
  result: String
}

type PipelineError {
  message: String
}

-- Note: pipelines are verified by the parser/typechecker,
-- but lowered to empty contract lists in the current VM release.
pipeline ${name}[PipelineInput, PipelineOutput, PipelineError] {
  step validate:  validate_input
  step enrich:    enrich_data
  step output:    produce_output
}
`,
    },
    {
      id: 'projection',
      label: 'Projection',
      icon: '���',
      description: 'Observed contract with TBackend reads',
      generate: (name, mod) => `module ${mod}

type EntityRecord {
  name: String
  value: Integer
}

type EntitySnapshot {
  id: String
  data: EntityRecord
  snapshot_at: String
}

def build_snapshot(record: EntityRecord, id: String) -> EntitySnapshot {
  {
    id:          id,
    data:        record,
    snapshot_at: "now"
  }
}

observed contract ${name} {
  input entity_id: String
  input date:      String

  read record: EntityRecord
    from "entity/{entity_id}"
    lifecycle :durable

  compute snap = build_snapshot(record, entity_id)

  snapshot snap = snap lifecycle :durable

  output snap: EntitySnapshot lifecycle :durable
}
`,
    },
    {
      id: 'windowed',
      label: 'Windowed Projection',
      icon: '���',
      description: 'Projection with calendar window and snapshot',
      generate: (name, mod) => `module ${mod}

type EventFact {
  event_type: String
  timestamp: Integer
}

type DailySnapshot {
  id: String
  date: String
  count: Integer
}

def aggregate_events(events: Collection[EventFact], id: String, date: String)
    -> DailySnapshot {
  let cnt = count(events)
  { id: id, date: date, count: cnt }
}

observed contract ${name} {
  input entity_id: String
  input date:      String

  escape stream_collection

  read events: Collection[EventFact]
    from "event/{entity_id}/{date}"
    lifecycle :window

  compute daily = aggregate_events(events, entity_id, date)

  window "${name} [day]" {
    kind     :calendar
    unit     :day
    on_close :snapshot
  }

  snapshot snap = daily lifecycle :durable

  output events: Collection[EventFact] lifecycle :window
  output snap: DailySnapshot           lifecycle :durable
}
`,
    },
    {
      id: 'validator',
      label: 'Validator',
      icon: '���',
      description: 'Input validation with Result monad',
      generate: (name, mod) => `module ${mod}

type InputData {
  value: String
}

type ValidationError {
  message: String
}

def validate(data: InputData) -> Result[InputData, ValidationError] {
  if data.value == "" {
    err({ message: "value cannot be empty" })
  } else {
    ok(data)
  }
}

contract ${name} {
  input data: InputData

  compute validated = validate(data)

  output validated: Result[InputData, ValidationError]
}
`,
    },
    {
      id: 'loop',
      label: 'Loop Contract',
      icon: '���',
      description: 'Iterative computation over a collection',
      generate: (name, mod) => `module ${mod}

contract ${name} {
  input items: Array[Integer]

  compute total = 0

  loop Accumulate in items max_steps: 1000 {
    compute total = total + item
  }

  output total: Integer
}
`,
    },
    {
      id: 'extension',
      label: 'Stdlib Extension',
      icon: '���',
      description: 'Module with def declarations (library)',
      generate: (name, mod) => `module ${mod}.${name}

-- ${name} library: declarative function implementations

def process(input: String) -> String {
  input
}

def validate(input: String) -> Result[String, String] {
  ok(input)
}

def transform(input: String, opts: String) -> String {
  input
}
`,
    },
  ]

  export let preselectedTemplateId: string = 'empty'

  let selectedTemplate = TEMPLATES[0]

  $: if (open && preselectedTemplateId) {
    const found = TEMPLATES.find(t => t.id === preselectedTemplateId)
    if (found) selectedTemplate = found
  }

  let fileName = ''
  let moduleName = ''
  let error = ''
  let creating = false

  $: contractName = toContractCase(fileName.replace(/\.ig$/, ''))
  $: moduleDefault = workspaceDir ? workspaceDir.split('/').pop() ?? 'MyApp' : 'MyApp'
  $: effectiveModule = moduleName.trim() || moduleDefault
  $: previewCode = selectedTemplate.generate(contractName || 'MyContract', effectiveModule)
  $: targetDir = currentFilePath
    ? currentFilePath.split('/').slice(0, -1).join('/')
    : workspaceDir

  function toContractCase(s: string): string {
    if (!s) return ''
    return s
      .replace(/[_\-\s]+(.)/g, (_, c: string) => c.toUpperCase())
      .replace(/^(.)/, (_, c: string) => c.toUpperCase())
  }

  function close() {
    open = false
    fileName = ''
    moduleName = ''
    error = ''
    selectedTemplate = TEMPLATES[0]
    dispatch('close')
  }

  async function create() {
    if (!fileName.trim()) { error = 'Enter a file name'; return }
    if (!targetDir) { error = 'Open a workspace first'; return }
    const cleanName = fileName.endsWith('.ig') ? fileName : `${fileName}.ig`
    const path = `${targetDir}/${cleanName}`
    creating = true
    error = ''
    try {
      await api.createFile(path, previewCode)
      dispatch('created', path)
      close()
    } catch (e) {
      error = String(e)
    } finally {
      creating = false
    }
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') close()
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) create()
  }
</script>

{#if open}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm"
    on:keydown={onKeydown}
    on:click|self={close}
  >
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
      class="bg-gray-900 border border-gray-700 rounded-xl shadow-2xl w-[760px] max-h-[84vh]
             flex flex-col overflow-hidden"
      on:click|stopPropagation={() => {}}
    >
      <!-- Header -->
      <div class="flex items-center justify-between px-5 py-3.5 border-b border-gray-800 shrink-0">
        <span class="text-sm font-bold text-gray-100 tracking-tight">New .ig File</span>
        <div class="flex items-center gap-3">
          <span class="text-[10px] text-gray-600">������ create �� Esc close</span>
          <button on:click={close} class="text-gray-500 hover:text-gray-300 transition-colors text-xs">���</button>
        </div>
      </div>

      <div class="flex flex-1 min-h-0 overflow-hidden">

        <!-- Template sidebar -->
        <div class="w-52 border-r border-gray-800 flex flex-col overflow-y-auto py-1.5 shrink-0 bg-gray-950/50">
          <div class="px-3 py-1 text-[9px] uppercase tracking-widest text-gray-600 font-bold">Templates</div>
          {#each TEMPLATES as t}
            <button
              on:click={() => selectedTemplate = t}
              class="flex items-start gap-2.5 px-3 py-2 text-left transition-colors
                     {selectedTemplate.id === t.id
                       ? 'bg-blue-600/25 border-r-2 border-blue-500 text-white'
                       : 'text-gray-400 hover:bg-gray-800/60 hover:text-gray-200'}"
            >
              <span class="text-sm mt-0.5 shrink-0 w-5 text-center">{t.icon}</span>
              <div class="min-w-0">
                <div class="text-xs font-semibold leading-tight truncate">{t.label}</div>
                <div class="text-[10px] text-gray-500 mt-0.5 leading-tight">{t.description}</div>
              </div>
            </button>
          {/each}
        </div>

        <!-- Right: form + preview -->
        <div class="flex-1 flex flex-col min-w-0 overflow-hidden">

          <!-- Form -->
          <div class="px-5 py-4 border-b border-gray-800 shrink-0 space-y-3">
            <div class="flex gap-3">
              <div class="flex-1">
                <label class="block text-[10px] text-gray-500 uppercase tracking-wider mb-1.5">File name</label>
                <!-- svelte-ignore a11y_autofocus -->
                <input
                  autofocus
                  bind:value={fileName}
                  placeholder="my_contract"
                  on:keydown={(e) => e.key === 'Enter' && !(e.metaKey || e.ctrlKey) && create()}
                  class="w-full bg-gray-950 border border-gray-700 rounded-lg px-3 py-2
                         text-sm font-mono outline-none focus:border-blue-500 transition-colors
                         placeholder-gray-700"
                />
                {#if contractName}
                  <div class="text-[10px] text-gray-600 mt-1">
                    Contract: <span class="text-blue-400 font-mono">{contractName}</span>
                  </div>
                {/if}
              </div>
              <div class="text-xs text-gray-600 pb-2 self-end">.ig</div>
            </div>

            <div>
              <label class="block text-[10px] text-gray-500 uppercase tracking-wider mb-1.5">Module</label>
              <input
                bind:value={moduleName}
                placeholder={moduleDefault}
                class="w-full bg-gray-950 border border-gray-700 rounded-lg px-3 py-2
                       text-sm font-mono outline-none focus:border-blue-500 transition-colors
                       placeholder-gray-700"
              />
            </div>

            <div class="text-[10px] text-gray-700 font-mono truncate" title={targetDir}>
              ���� {targetDir || '��� open a workspace first'}
            </div>
          </div>

          <!-- Code preview -->
          <div class="flex-1 min-h-0 overflow-auto bg-gray-950">
            <div class="px-5 py-2 border-b border-gray-800/60 bg-gray-900/50 shrink-0">
              <span class="text-[9px] uppercase tracking-widest text-gray-600 font-bold">Preview</span>
            </div>
            <pre class="text-xs text-gray-300 font-mono leading-relaxed p-5 whitespace-pre">{previewCode}</pre>
          </div>

          <!-- Footer -->
          <div class="px-5 py-3 border-t border-gray-800 flex items-center gap-2 shrink-0 bg-gray-900/50">
            {#if error}
              <span class="text-red-400 text-xs flex-1">{error}</span>
            {:else}
              <div class="flex-1"></div>
            {/if}
            <button
              on:click={close}
              class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 rounded-lg text-xs
                     transition-colors text-gray-300"
            >
              Cancel
            </button>
            <button
              on:click={create}
              disabled={creating || !fileName.trim() || !targetDir}
              class="px-4 py-1.5 bg-blue-700 hover:bg-blue-600 disabled:bg-gray-800
                     disabled:text-gray-600 rounded-lg text-xs font-semibold
                     transition-colors flex items-center gap-1.5"
            >
              {#if creating}<span class="animate-spin text-[10px]">���</span>{/if}
              Create File
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
{/if}
