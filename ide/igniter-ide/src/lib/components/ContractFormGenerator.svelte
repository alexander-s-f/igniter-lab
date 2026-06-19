<!-- igniter-lab/igniter-ide/src/lib/components/ContractFormGenerator.svelte -->
<script lang="ts">
  import { onMount } from 'svelte'
  import { api } from '$lib/api'
  import type { WorkspaceConfig, FileEntry } from '$lib/types'

  // Svelte 5 Props
  let { workspace }: { workspace: WorkspaceConfig | null } = $props()

  interface InputPort {
    name: string
    required: boolean
    type_tag: string
  }

  interface ContractData {
    contract_id: string
    name?: string
    input_ports?: InputPort[]
    type_signature?: {
      inputs?: Record<string, string>
    }
  }

  interface ContractOption {
    name: string
    path: string
  }

  // Reactive states using Svelte 5 $state
  let availableContracts = $state<ContractOption[]>([])
  let selectedContractPath = $state('')
  let contractData = $state<ContractData | null>(null)
  let loadingContracts = $state(false)
  let loadingContract = $state(false)
  let scanError = $state<string | null>(null)
  let loadError = $state<string | null>(null)

  // Form states
  let formValues = $state<Record<string, any>>({})
  let formErrors = $state<Record<string, string>>({})
  let arrayInputs = $state<Record<string, string[]>>({})
  let copied = $state(false)

  // Scan workspace when root_dir updates
  $effect(() => {
    if (workspace?.root_dir) {
      scanWorkspaceContracts()
    }
  })

  // Deep scanner for finding contracts/*.json inside compiled out/
  async function scanWorkspaceContracts() {
    if (!workspace?.root_dir) return
    loadingContracts = true
    scanError = null
    availableContracts = []
    selectedContractPath = ''
    contractData = null

    try {
      const outDir = `${workspace.root_dir}/igniter-compiler/out`
      const contractsList: ContractOption[] = []

      async function walk(dirPath: string) {
        let tree: FileEntry[] = []
        try {
          tree = await api.listDirTree(dirPath)
        } catch {
          // If directory doesn't exist yet, skip
          return
        }

        for (const entry of tree) {
          if (entry.entry_type === 'dir') {
            await walk(entry.path)
          } else if (entry.entry_type === 'file' && entry.path.endsWith('.json')) {
            // Check if it lies within a contracts folder
            const pathParts = entry.path.split('/')
            const parentIndex = pathParts.indexOf('contracts')
            if (parentIndex !== -1 && parentIndex === pathParts.length - 2) {
              contractsList.push({
                name: entry.name.replace('.json', ''),
                path: entry.path
              })
            }
          }
        }
      }

      await walk(outDir)
      availableContracts = contractsList

      if (contractsList.length === 0) {
        scanError = 'No compiled contract JSON files found. Run the compiler first to generate artifacts under igniter-compiler/out/.'
      }
    } catch (err: any) {
      scanError = `Workspace scan failed: ${err?.message || err}`
    } finally {
      loadingContracts = false
    }
  }

  // Handle selection and parse contract fields
  async function handleSelectContract() {
    if (!selectedContractPath) {
      contractData = null
      resetForm()
      return
    }

    loadingContract = true
    loadError = null
    contractData = null
    resetForm()

    try {
      const content = await api.readFile(selectedContractPath)
      const parsed = JSON.parse(content) as ContractData

      if (!parsed.contract_id && !parsed.name) {
        throw new Error('Selected file does not appear to be a valid Igniter Contract JSON (missing contract_id).')
      }

      contractData = parsed
      initializeForm(parsed)
    } catch (err: any) {
      loadError = `Failed to load contract: ${err?.message || err}`
    } finally {
      loadingContract = false
    }
  }

  function resetForm() {
    formValues = {}
    formErrors = {}
    arrayInputs = {}
  }

  // Parse type schemas (inputs, input_ports)
  function getPorts(data: ContractData): InputPort[] {
    if (data.input_ports && Array.isArray(data.input_ports)) {
      return data.input_ports
    }
    // Fallback if only type_signature is present
    if (data.type_signature?.inputs) {
      return Object.entries(data.type_signature.inputs).map(([name, type_tag]) => ({
        name,
        type_tag,
        required: true // Assume required in fallback
      }))
    }
    return []
  }

  function initializeForm(data: ContractData) {
    const ports = getPorts(data)
    ports.forEach(p => {
      const lowerType = p.type_tag.toLowerCase()
      if (lowerType === 'boolean') {
        formValues[p.name] = false
      } else if (lowerType.startsWith('array[') || lowerType.startsWith('collection[')) {
        arrayInputs[p.name] = []
        formValues[p.name] = []
      } else {
        formValues[p.name] = ''
      }
    })
  }

  // Dynamic Array Handlers
  function addArrayRow(fieldName: string) {
    if (!arrayInputs[fieldName]) {
      arrayInputs[fieldName] = []
    }
    arrayInputs[fieldName] = [...arrayInputs[fieldName], '']
  }

  function removeArrayRow(fieldName: string, index: number) {
    arrayInputs[fieldName] = arrayInputs[fieldName].filter((_, i) => i !== index)
  }

  function handleArrayRowChange(fieldName: string, index: number, val: string) {
    arrayInputs[fieldName][index] = val
  }

  // Extract inner array type: Array[Integer] -> Integer
  function getArrayInnerType(typeTag: string): string {
    const match = typeTag.match(/^(?:Array|Collection)\[(.*)\]$/i)
    return match ? match[1].trim() : 'String'
  }

  // Check if type tag is supported
  function isSupportedType(typeTag: string): boolean {
    const t = typeTag.trim().toLowerCase()
    if (t === 'string' || t === 'integer' || t === 'boolean' || t === 'float') return true
    if (t.startsWith('decimal')) return true
    if (t.startsWith('array[') || t.startsWith('collection[')) {
      const inner = getArrayInnerType(typeTag)
      return isSupportedType(inner)
    }
    return false
  }

  // Form Client-side Validator
  let validationSummary = $derived.by(() => {
    if (!contractData) return { valid: false, errors: {}, unsupported: [] }

    const errors: Record<string, string> = {}
    const unsupported: string[] = []
    const ports = getPorts(contractData)

    ports.forEach(p => {
      const typeTag = p.type_tag
      const val = formValues[p.name]

      // 1. Check if type is supported
      if (!isSupportedType(typeTag)) {
        unsupported.push(p.name)
        return
      }

      // 2. Required Check
      const isArray = typeTag.toLowerCase().startsWith('array[') || typeTag.toLowerCase().startsWith('collection[')
      const isEmpty = isArray
        ? (!arrayInputs[p.name] || arrayInputs[p.name].length === 0)
        : (val === undefined || val === null || String(val).trim() === '')

      if (p.required && isEmpty) {
        errors[p.name] = 'Field is required'
        return
      }

      // Skip type validations if field is optional and empty
      if (isEmpty) return

      // 3. Type validations
      if (typeTag.toLowerCase() === 'integer') {
        if (!/^-?\d+$/.test(String(val).trim())) {
          errors[p.name] = 'Must be a valid integer (no decimals)'
        }
      } else if (typeTag.toLowerCase().startsWith('decimal') || typeTag.toLowerCase() === 'float') {
        if (!/^-?\d+(\.\d+)?$/.test(String(val).trim())) {
          errors[p.name] = 'Must be a valid decimal number'
        }
      } else if (isArray) {
        const innerType = getArrayInnerType(typeTag)
        const rows = arrayInputs[p.name] || []

        for (let i = 0; i < rows.length; i++) {
          const rowVal = rows[i].trim()
          if (rowVal === '') {
            errors[`${p.name}_${i}`] = 'Row value cannot be empty'
          } else if (innerType.toLowerCase() === 'integer') {
            if (!/^-?\d+$/.test(rowVal)) {
              errors[`${p.name}_${i}`] = 'Must be an integer'
            }
          } else if (innerType.toLowerCase().startsWith('decimal') || innerType.toLowerCase() === 'float') {
            if (!/^-?\d+(\.\d+)?$/.test(rowVal)) {
              errors[`${p.name}_${i}`] = 'Must be a decimal'
            }
          }
        }
      }
    })

    const hasErrors = Object.keys(errors).length > 0
    const hasUnsupported = unsupported.length > 0

    return {
      valid: !hasErrors && !hasUnsupported,
      errors,
      unsupported
    }
  })

  // JSON Input Packet Builder
  let jsonPacket = $derived.by(() => {
    if (!contractData) return ''

    const ports = getPorts(contractData)
    const values: Record<string, any> = {}

    ports.forEach(p => {
      const typeTag = p.type_tag
      const val = formValues[p.name]

      if (!isSupportedType(typeTag)) return

      const isArray = typeTag.toLowerCase().startsWith('array[') || typeTag.toLowerCase().startsWith('collection[')
      if (isArray) {
        const innerType = getArrayInnerType(typeTag)
        const rows = arrayInputs[p.name] || []
        values[p.name] = rows.map(r => {
          const trim = r.trim()
          if (trim === '') return null
          if (innerType.toLowerCase() === 'integer') return parseInt(trim, 10)
          if (innerType.toLowerCase().startsWith('decimal') || innerType.toLowerCase() === 'float') return parseFloat(trim)
          if (innerType.toLowerCase() === 'boolean') return trim.toLowerCase() === 'true'
          return trim
        }).filter(r => r !== null)
      } else {
        const strVal = String(val).trim()
        if (strVal === '') {
          values[p.name] = null
        } else if (typeTag.toLowerCase() === 'integer') {
          values[p.name] = parseInt(strVal, 10)
        } else if (typeTag.toLowerCase().startsWith('decimal') || typeTag.toLowerCase() === 'float') {
          values[p.name] = parseFloat(strVal)
        } else if (typeTag.toLowerCase() === 'boolean') {
          values[p.name] = !!val
        } else {
          values[p.name] = strVal
        }
      }
    })

    const packet = {
      contract_name: contractData.contract_id || contractData.name || 'Unknown',
      input_values: values,
      validation_status: validationSummary.valid ? 'valid' : 'invalid',
      unsupported_fields: validationSummary.unsupported,
      authority_marker: 'lab_only_non_execution',
      generated_at: new Date().toISOString()
    }

    return JSON.stringify(packet, null, 2)
  })

  // Copy helper
  async function copyPacket() {
    try {
      await navigator.clipboard.writeText(jsonPacket)
      copied = true
      setTimeout(() => copied = false, 2000)
    } catch {}
  }
</script>

<div class="flex flex-col w-full h-full min-h-0 bg-ink text-warm-3 font-mono">

  <!-- Selection Bar -->
  <div class="flex items-center gap-3 px-3 py-2 border-b border-ink-line bg-ink-1 shrink-0 select-none">
    <span class="text-xs text-warm">Select Compiled Contract:</span>
    <select
      bind:value={selectedContractPath}
      onchange={handleSelectContract}
      disabled={loadingContracts}
      class="bg-ink border border-ink-line rounded px-2 py-1 text-xs text-grey-3 font-mono h-7 outline-none min-w-60 focus:border-ignite"
    >
      <option value="">��� select ���</option>
      {#each availableContracts as opt}
        <option value={opt.path}>{opt.name}</option>
      {/each}
    </select>
    <button
      onclick={scanWorkspaceContracts}
      disabled={loadingContracts}
      class="h-7 px-3 bg-ink-2 hover:bg-ink-3 border border-ink-line text-warm hover:text-warm-3 rounded text-xs transition-colors cursor-pointer flex items-center gap-1.5"
    >
      {#if loadingContracts}
        <span class="animate-pulse">��� Scanning...</span>
      {:else}
        <span>��� Rescan</span>
      {/if}
    </button>
  </div>

  <!-- Main View Area -->
  <div class="flex-1 flex min-h-0 overflow-hidden divide-x divide-ink-line">

    <!-- Left Column: Generated Form -->
    <div class="w-1/2 flex flex-col min-h-0 bg-ink-1 overflow-hidden">
      <div class="px-3 py-1.5 border-b border-ink-line bg-ink-2 shrink-0 flex justify-between items-center select-none">
        <span class="text-xs font-bold text-warm uppercase tracking-wider">Generated Input Form</span>
        <span class="text-[9px] text-warm/40 font-mono bg-ink-1 border border-ink-line px-1.5 rounded">Client-side validation</span>
      </div>

      <div class="flex-1 p-6 overflow-y-auto ig-field">
        {#if scanError}
          <div class="border border-oof/40 bg-oof/5 p-4 rounded-lg text-xs text-oof font-mono relative reg">
            <div class="tr"></div><div class="bl"></div>
            <span class="font-bold block mb-1">������ Scan Warning</span>
            <p>{scanError}</p>
          </div>
        {:else if loadError}
          <div class="border border-oof/40 bg-oof/5 p-4 rounded-lg text-xs text-oof font-mono relative reg">
            <div class="tr"></div><div class="bl"></div>
            <span class="font-bold block mb-1">������ Load Error</span>
            <p>{loadError}</p>
          </div>
        {:else if loadingContract}
          <div class="text-warm/40 italic text-center py-12 text-xs">
            <span class="animate-pulse inline-block">��� Parsing contract schema...</span>
          </div>
        {:else if contractData}
          <div class="max-w-xl mx-auto bg-ink-1 border border-ink-line rounded-lg shadow-xl p-5 relative">
            <h2 class="text-sm font-bold text-ignite border-b border-ink-line pb-2 mb-4 flex items-center gap-2">
              <span>���</span>
              <span>{contractData.contract_id || contractData.name}</span>
            </h2>

            <form onsubmit={(e) => e.preventDefault()} class="space-y-4 text-xs font-mono">
              {#each getPorts(contractData) as port}
                <div class="space-y-1.5">
                  <div class="flex justify-between items-center">
                    <label class="text-grey-3 font-semibold flex items-center gap-1">
                      <span>{port.name}</span>
                      {#if port.required}
                        <span class="text-oof" title="Required">*</span>
                      {/if}
                    </label>
                    <span class="text-[9px] bg-ink border border-ink-line text-grey px-1 py-0.5 rounded font-bold uppercase">{port.type_tag}</span>
                  </div>

                  <!-- Render inputs based on type -->
                  {#if !isSupportedType(port.type_tag)}
                    <!-- Fail-closed Unsupported state -->
                    <div class="border border-oof/40 bg-oof/5 p-2.5 rounded text-[11px] text-oof font-bold relative">
                      ������ Unsupported type: '{port.type_tag}'. Field cannot be serialized.
                    </div>
                  {:else if port.type_tag.toLowerCase() === 'boolean'}
                    <label class="flex items-center gap-2 p-2 bg-ink border border-ink-line rounded cursor-pointer hover:border-line select-none">
                      <input
                        type="checkbox"
                        bind:checked={formValues[port.name]}
                        class="accent-ignite bg-ink rounded border-ink-line"
                      />
                      <span class="text-grey-2">Enable / True</span>
                    </label>
                  {:else if port.type_tag.toLowerCase().startsWith('array[') || port.type_tag.toLowerCase().startsWith('collection[')}
                    <!-- Array / Collection Row Editor -->
                    <div class="space-y-2 border border-ink-line/60 rounded p-2.5 bg-ink">
                      <div class="flex justify-between items-center">
                        <span class="text-[10px] text-grey">List items:</span>
                        <button
                          type="button"
                          onclick={() => addArrayRow(port.name)}
                          class="px-2 py-0.5 bg-ignite/15 hover:bg-ignite/25 border border-ignite/30 text-ignite rounded text-[10px] cursor-pointer transition-colors"
                        >
                          + Add Row
                        </button>
                      </div>

                      {#if !arrayInputs[port.name] || arrayInputs[port.name].length === 0}
                        <div class="text-[10px] text-grey/40 italic py-2">No rows added yet.</div>
                      {:else}
                        <div class="space-y-1.5">
                          {#each arrayInputs[port.name] as row, idx}
                            <div class="flex items-center gap-2">
                              <input
                                type="text"
                                value={row}
                                oninput={(e) => handleArrayRowChange(port.name, idx, (e.target as HTMLInputElement).value)}
                                placeholder={`Item ${idx + 1} (${getArrayInnerType(port.type_tag)})`}
                                class="flex-1 bg-ink-1 border border-ink-line rounded px-2 py-1 text-xs text-warm-3 font-mono h-7 min-w-0 focus:border-line"
                              />
                              <button
                                type="button"
                                onclick={() => removeArrayRow(port.name, idx)}
                                class="text-warm/40 hover:text-oof text-sm font-bold w-6 h-7 flex items-center justify-center rounded hover:bg-ink-2 cursor-pointer shrink-0 transition-colors"
                                title="Remove row"
                              >
                                ���
                              </button>
                            </div>
                            <!-- Inline row errors -->
                            {#if validationSummary.errors[`${port.name}_${idx}`]}
                              <div class="text-[10px] text-oof font-bold pl-1">
                                ��� {validationSummary.errors[`${port.name}_${idx}`]}
                              </div>
                            {/if}
                          {/each}
                        </div>
                      {/if}
                    </div>
                  {:else}
                    <!-- Primitives (String, Integer, Decimal) -->
                    <input
                      type={port.type_tag.toLowerCase() === 'string' ? 'text' : 'number'}
                      step={port.type_tag.toLowerCase() === 'integer' ? '1' : 'any'}
                      bind:value={formValues[port.name]}
                      placeholder={`Enter ${port.name} (${port.type_tag})`}
                      class="w-full bg-ink border border-ink-line rounded px-3 py-1.5 text-xs text-warm-3 font-mono focus:border-ignite outline-none"
                    />
                  {/if}

                  <!-- Generic errors -->
                  {#if validationSummary.errors[port.name]}
                    <div class="text-[10px] text-oof font-bold pl-1">
                      ��� {validationSummary.errors[port.name]}
                    </div>
                  {/if}
                </div>
              {/each}
            </form>
          </div>
        {:else}
          <div class="flex flex-col items-center justify-center p-8 text-center h-48 select-none">
            <span class="text-3xl mb-2">����</span>
            <p class="text-xs text-warm">Select a compiled contract JSON from the dropdown to generate the form.</p>
          </div>
        {/if}
      </div>
    </div>

    <!-- Right Column: Generated JSON Input Packet -->
    <div class="w-1/2 flex flex-col min-h-0 bg-ink overflow-hidden">
      <div class="px-3 py-1.5 border-b border-ink-line bg-ink-2 shrink-0 flex justify-between items-center select-none">
        <span class="text-xs font-bold text-warm uppercase tracking-wider">JSON Input Packet Preview</span>
        <button
          onclick={copyPacket}
          disabled={!contractData}
          class="h-5 px-2.5 bg-core/15 hover:bg-core/25 border border-core/30 text-core disabled:border-ink-line disabled:text-warm/30 rounded text-[10px] font-semibold cursor-pointer transition-colors flex items-center gap-1"
        >
          {#if copied}
            <span>��� Copied</span>
          {:else}
            <span>���� Copy JSON</span>
          {/if}
        </button>
      </div>

      <div class="flex-1 p-6 overflow-y-auto flex flex-col min-h-0 relative">
        {#if contractData}
          <!-- Sandboxed static non-execution header (GUIF-9) -->
          <div class="mb-4 border border-amber/40 bg-amber/5 p-3.5 rounded-lg text-xs text-amber font-mono relative reg shrink-0 select-none">
            <div class="tr"></div><div class="bl"></div>
            <div class="flex items-center gap-2 mb-1.5 font-bold uppercase tracking-wider text-[11px]">
              <span>������</span>
              <span>Lab Sandbox Non-Execution Panel</span>
            </div>
            <p class="text-[10px] text-grey-2 leading-relaxed">
              This generator generates static JSON payloads for testing type schema lowering.
              <strong>No VM execution, runtime dispatch, or contract side-effects occur.</strong>
            </p>
          </div>

          <!-- Status Indicator badge -->
          <div class="mb-4 flex items-center justify-between bg-ink-1 border border-ink-line p-2.5 rounded shrink-0 select-none">
            <span class="text-xs text-grey">Validation Status:</span>
            {#if validationSummary.valid}
              <span class="text-[10px] bg-core/15 text-core border border-core/30 px-2 py-0.5 rounded font-bold uppercase tracking-wider">��� VALID PACKET</span>
            {:else}
              <span class="text-[10px] bg-oof/15 text-oof border border-oof/30 px-2 py-0.5 rounded font-bold uppercase tracking-wider">��� INVALID PACKET</span>
            {/if}
          </div>

          <!-- JSON Block -->
          <div class="flex-1 bg-ink-1 border border-ink-line rounded-lg p-4 font-mono text-[11px] overflow-auto select-text">
            <pre class="text-grey-3 leading-relaxed whitespace-pre-wrap">{jsonPacket}</pre>
          </div>
        {:else}
          <div class="flex-1 flex flex-col items-center justify-center p-8 text-center text-xs text-warm/30 italic select-none">
            No packet generated. Please select a contract first.
          </div>
        {/if}
      </div>
    </div>

  </div>
</div>

<style>
  /* Local scrollbar overrides for premium styling */
  ::-webkit-scrollbar {
    width: 6px;
    height: 6px;
  }
  ::-webkit-scrollbar-track {
    background: var(--ink-1);
  }
  ::-webkit-scrollbar-thumb {
    background: var(--line);
    border-radius: 3px;
  }
  ::-webkit-scrollbar-thumb:hover {
    background: var(--line-2);
  }
</style>
