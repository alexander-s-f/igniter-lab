import { writable } from 'svelte/store'
import type { DiagnosticInfo } from '../types'

export interface BuildRecord {
  id: string
  contractName: string
  ts: number
  success: boolean
  message: string
  sourceLength?: number
  artifactPath?: string
}

export interface RunRecord {
  id: string
  contractName: string
  ts: number
  inputs: Record<string, any>
  result: any
  durationMs: number
  error?: string
}

export interface DebugEvent {
  id: string
  type: 'compile' | 'run'
  timestamp: number
  contractName: string
  success: boolean
  durationMs: number

  // Compile specific fields
  sourceLength?: number
  sourceHash?: string
  command?: string
  diagnosticsCount?: number
  artifactDir?: string

  // Run specific fields
  inputs?: any
  runtime?: string
  result?: any
  error?: string
  errorStage?: string

  // Observability & Boundary Phase fields (P10)
  boundaryPhase?: 'compiler' | 'loader' | 'execution' | 'none'
  diagnostics?: DiagnosticInfo[]
  passportSummary?: any
  loaderDecision?: string
  ffiObservations?: any[]
}

export const buildsStore = writable<BuildRecord[]>([])
export const runsStore   = writable<RunRecord[]>([])

const isBrowser = typeof window !== 'undefined'
const initialEvents = isBrowser ? JSON.parse(localStorage.getItem('igniter_debug_events') || '[]') : []
export const debuggerStore = writable<DebugEvent[]>(initialEvents)

if (isBrowser) {
  debuggerStore.subscribe(val => {
    localStorage.setItem('igniter_debug_events', JSON.stringify(val))
  })
}

export const artifacts = {
  addBuild(r: Omit<BuildRecord, 'id'>) {
    buildsStore.update(b => [{ id: crypto.randomUUID(), ...r }, ...b].slice(0, 100))
  },
  addRun(r: Omit<RunRecord, 'id'>) {
    runsStore.update(rs => [{ id: crypto.randomUUID(), ...r }, ...rs].slice(0, 50))
  },
  addDebugEvent(r: Omit<DebugEvent, 'id'>) {
    debuggerStore.update(events => [{ id: crypto.randomUUID(), ...r }, ...events].slice(0, 200))
  },
  clearDebugEvents() {
    debuggerStore.set([])
  }
}
