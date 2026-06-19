/**
 * Blueprint IR ��� Intermediate Representation for Igniter Lang contracts.
 *
 * This is the single source of truth between:
 *   parser.ts  ��� produces BpGraph from .ig source
 *   layout.ts  ��� assigns x/y positions to nodes
 *   codegen.ts ��� generates .ig source from BpGraph
 *   Canvas UI  ��� renders and mutates BpGraph
 *
 * Design rule: IR types must be serialisable (no functions, no cycles).
 */

// ������ Node kinds ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

export type NodeKind =
  | 'input'    // input name: Type
  | 'compute'  // compute name = expr
  | 'output'   // output name: Type [lifecycle]
  | 'read'     // read name: Type from "path" lifecycle :durable
  | 'snapshot' // snapshot name = expr lifecycle :durable
  | 'window'   // window "label" { ... }
  | 'loop'     // loop Name in items max_steps: N { ... }
  | 'step'     // step name: fn  (inside pipeline)
  | 'escape'   // escape keyword
  | 'invariant' // invariant predicate


// ������ Port ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

export interface Port {
  id:    string    // unique within node, e.g. "in:vendor_id" or "out"
  label: string    // display label
  type?: string    // optional type annotation
}

// ������ Node ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

export interface BpNode {
  id:       string     // globally unique, e.g. "BidSummary__gross_bid"
  kind:     NodeKind
  name:     string     // as written in .ig source
  x:        number     // canvas position ��� set by layout, persisted in canvas state
  y:        number
  width:    number
  height:   number
  inPorts:  Port[]     // left side connections
  outPorts: Port[]     // right side connections (usually one "out" port)
  props:    Record<string, string>  // kind-specific: type, expr, from, lifecycle, ���
  sourceLine: number   // line number in source for go-to-source
}

// ������ Edge ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

export interface BpEdge {
  id:         string
  fromNodeId: string
  fromPort:   string   // usually 'out'
  toNodeId:   string
  toPort:     string   // 'in:<dep_name>'
}

// ������ Contract / Pipeline block ���������������������������������������������������������������������������������������������������������������������������������������������������

export type ContractKind = 'contract' | 'observed_contract' | 'pipeline'

export interface BpContract {
  id:    string         // usually the contract name
  name:  string
  kind:  ContractKind
  nodes: BpNode[]
  edges: BpEdge[]
  // Canvas-only layout offset for multi-contract files
  offsetX: number
  offsetY: number
}

// ������ File-level graph ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

export interface FunctionDef {
  name:      string
  signature: string   // raw text of the signature line(s)
  line:      number
}

export interface BpGraph {
  filePath:   string
  moduleDecl: string
  imports:    string[]
  defs:       FunctionDef[]
  contracts:  BpContract[]
}

// ������ Sizing constants (lego: override per kind in NODE_KIND_META) ������������������������������������������

export const NODE_WIDTH   = 200   // fixed card width
export const NODE_MIN_H   = 40    // minimum height when no ports
export const PORT_ROW_H   = 24    // height per port row
export const HEADER_H     = 34    // card header height
export const PROP_ROW_H   = 18    // height per property line shown
export const MAX_PROPS    = 2     // max prop lines to show in card (rest truncated)

export function nodeHeight(node: BpNode): number {
  const portRows = Math.max(node.inPorts.length, node.outPorts.length, 1)
  const propRows = Math.min(Object.keys(node.props).length, MAX_PROPS)
  return HEADER_H + portRows * PORT_ROW_H + propRows * PROP_ROW_H + 12
}

// ������ Port helpers ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

export function outPort(label = 'out', type?: string): Port {
  return { id: 'out', label, type }
}

export function inPort(dep: string, type?: string): Port {
  return { id: `in:${dep}`, label: dep, type }
}

// ������ Empty graph ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

export function emptyGraph(filePath = ''): BpGraph {
  return { filePath, moduleDecl: '', imports: [], defs: [], contracts: [] }
}
