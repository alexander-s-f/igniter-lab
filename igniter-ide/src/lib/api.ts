import { invoke } from '@tauri-apps/api/core'
import type { ContractInfo, FactInfo, ObsInfo, StatusInfo, WorkspaceConfig, WorkspaceLoadResult, DiagnosticInfo, SystemGraph, TracedResult, AppConfig, FileEntry, RedactedTraceReceipt } from './types'

export const api = {
  getStatus: () =>
    invoke<StatusInfo>('get_status'),

  listContracts: () =>
    invoke<ContractInfo[]>('list_contracts'),

  loadContract: (source: string, name: string, workspaceDir?: string) =>
    invoke<any>('load_contract', { sourceCode: source, contractName: name, workspaceDir }),

  loadContractFromFile: (path: string, name: string, workspaceDir?: string) =>
    invoke<any>('load_contract_from_file', { path, contractName: name, workspaceDir }),

  dispatch: (name: string, inputs: string) =>
    invoke<any>('dispatch_contract', { contractName: name, inputsJson: inputs }),

  writeFact: (store: string, key: string, value: string) =>
    invoke<string>('write_fact', { store, key, valueJson: value }),

  readFacts: (store: string, key: string, asOf?: number) =>
    invoke<FactInfo[]>('read_facts', { store, key, asOf }),

  listObservations: () =>
    invoke<ObsInfo[]>('list_observations'),

  clearObservations: () =>
    invoke<void>('clear_observations'),

  checkpoint: (path: string) =>
    invoke<void>('checkpoint_machine', { path }),

  resume: (path: string) =>
    invoke<string>('resume_machine', { path }),

  getContractIr: (name: string) => invoke<any>('get_contract_ir', { name }),

  openWorkspace: (dir: string) => invoke<WorkspaceConfig>('open_workspace', { dir }),
  createWorkspace: (dir: string, name: string) => invoke<WorkspaceConfig>('create_workspace', { dir, name }),
  listIgFiles: (dir: string) => invoke<string[]>('list_ig_files', { dir }),
  readFile: (path: string) => invoke<string>('read_file', { path }),
  writeFile: (path: string, content: string) => invoke<void>('write_file', { path, content }),
  loadWorkspaceContracts: (config: WorkspaceConfig) => invoke<WorkspaceLoadResult[]>('load_workspace_contracts', { config }),
  checkSource: (sourceCode: string, contractName: string) => invoke<DiagnosticInfo[]>('check_source', { sourceCode, contractName }),

  // Feature 1: System Graph
  getSystemGraph: () => invoke<SystemGraph>('get_system_graph'),

  // Feature 2: Execution Tracer
  dispatchTraced: (contractName: string, inputs: any) =>
    invoke<TracedResult>('dispatch_traced', { contractName, inputs }),

  // Feature 3: App Manager
  createApp: (dir: string, name: string, description: string) =>
    invoke<AppConfig>('create_app', { dir, name, description }),
  listApps: (dir: string) => invoke<AppConfig[]>('list_apps', { dir }),

  // Feature 4: File Tree
  listDirTree: (dir: string) => invoke<FileEntry[]>('list_dir_tree', { dir }),
  createFile: (path: string, content: string) => invoke<void>('create_file', { path, content }),
  deleteFile: (path: string) => invoke<void>('delete_file', { path }),
  renameFile: (from: string, to: string) => invoke<void>('rename_file', { from, to }),
  readPlaybackReceipt: () => invoke<any>('read_playback_receipt'),
  getTelemetryHistory: () => invoke<RedactedTraceReceipt[]>('get_telemetry_history'),
  ingestExternalTraceEvent: (payloadJson: string) =>
    invoke<RedactedTraceReceipt>('ingest_external_trace_event', { payloadJson }),
  ingestAdaptedVmTrace: (payloadJson: string) =>
    invoke<RedactedTraceReceipt>('ingest_adapted_vm_trace', { payloadJson }),
  runMockVmRunnerDispatch: (transactionId: string, status: string, producerId: string, signature: string) =>
    invoke<RedactedTraceReceipt>('run_mock_vm_runner_dispatch', { transactionId, status, producerId, signature }),
}
