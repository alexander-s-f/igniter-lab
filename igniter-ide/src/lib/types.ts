export interface ContractInfo {
  name: string
  fragment_class: string
}

export interface FactInfo {
  id: string
  store: string
  key: string
  value: any
  transaction_time: number
  valid_time?: number
  causation?: string
}

export interface ObsInfo {
  id: string
  kind: string
  value: any
  timestamp: number
}

export interface StatusInfo {
  backend: string
  facts_count: number
  contracts_count: number
  observations_count: number
}

export interface DispatchResult {
  output: any
  error?: string
}

export interface WorkspaceConfig {
  name: string
  version: string
  backend: { backend_type: string; path?: string; address?: string }
  contracts: string[]
  auto_load: boolean
  root_dir: string
}

export interface WorkspaceLoadResult {
  path: string
  contract_name: string
  success: boolean
  message: string
}

export interface DiagnosticInfo {
  rule: string
  message: string
  severity: 'error' | 'warning' | 'info'
  line?: number
  col?: number
}

// ������ Feature 4: File Tree ������������������������������������������������������������������������������������������������������������������������������������������������������������������

export interface FileEntry {
  name: string
  path: string
  entry_type: 'file' | 'dir'
  children: FileEntry[]
  extension: string | null
}

// ������ IDE Settings ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

export interface IdeSettings {
  editor: {
    tabSize: 2 | 4
    fontSize: number
    wordWrap: 'on' | 'off'
    minimap: boolean
    fontFamily: string
  }
  appearance: {
    accentColor: 'blue' | 'purple' | 'green' | 'cyan'
  }
  ai: {
    provider: 'anthropic' | 'openai' | 'ollama'
    model: string
    apiKey: string
    baseUrl: string
  }
  workflow: {
    autoSave: boolean
    autoSaveDelay: number
    autoCompile: boolean
    autoSnapshot: boolean
  }
}

// ������ Feature 1: System Graph ���������������������������������������������������������������������������������������������������������������������������������������������������������

export interface SystemNode {
  id: string
  contract_name: string
  fragment_class: string
  inputs: string[]
  outputs: string[]
  node_count: number
}

export interface SystemEdge {
  from: string
  to: string
  label: string
}

export interface SystemGraph {
  nodes: SystemNode[]
  edges: SystemEdge[]
}

// ������ Feature 2: Execution Tracer ���������������������������������������������������������������������������������������������������������������������������������������������

export interface TraceStep {
  node: string
  kind: string
  fragment_class: string
  deps: string[]
  order: number
  value_preview: string
}

export interface TracedResult {
  result: any
  trace: TraceStep[]
  total_ms: number
  observations: string[]
  contract_name: string
  success: boolean
  boundary_phase: 'compiler' | 'loader' | 'execution' | 'none'
  error_message?: string
  diagnostics: DiagnosticInfo[]
  passport_summary?: any
  loader_decision?: string
  ffi_observations?: any[]
}

// ������ Feature 3: App Manager ������������������������������������������������������������������������������������������������������������������������������������������������������������

export interface SwarmConfig {
  enabled: boolean
  instances: number
  topology: string
}

// ������ Build Artifact (on-disk) ���������������������������������������������������������������������������������������������������������������������������������������������������������

export interface ArtifactFile {
  contract: string
  compiledAt: string
  sourceLength: number
  ir: any
  filePath: string
}

export interface AppConfig {
  name: string
  version: string
  description: string
  contracts_dir: string
  backend: { backend_type: string; path?: string; address?: string }
  swarm: SwarmConfig
  root_dir: string
}

export interface RedactedTraceReceipt {
  trace_id: string
  contract_id: string
  status: string
  timestamp: string
  target_views?: string[]
  selected_slot_keys: string[]
  outputs_digest: string
  diagnostics_digest: string
  redaction_policy: string
  receipt_id?: string
  event_type: 'attempted_trace_events' | 'applied_trace_events'
}

export interface IntrospectionBounds {
  x: number
  y: number
  w: number
  h: number
}

export interface IntrospectionNode {
  id: string
  type: string
  parent: string | null
  z_index: number
  computed_bounds: IntrospectionBounds | null
  slot_bound: boolean
  referenced_slots: string[]
  scoped_slots: string[]
  containment: 'contained' | 'overflow' | 'N/A'
  overflow_allowance: 'allow' | 'clip' | 'none'
  allow_structural_overwrites: boolean
  status: 'active' | 'skip'
}

export interface IntrospectionReceipt {
  view_id: string
  scene_digest: string
  node_count: number
  nodes: Record<string, IntrospectionNode>
  non_claims: string[]
}

