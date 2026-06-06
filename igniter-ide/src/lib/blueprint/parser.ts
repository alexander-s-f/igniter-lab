/**
 * parser.ts ��� Igniter Lang (.ig) ��� BpGraph
 *
 * Pure function: no side effects, no DOM, no Svelte.
 * Extensibility: add entries to LINE_PARSERS or BODY_PARSERS.
 */

import {
  type BpGraph, type BpContract, type BpNode, type BpEdge,
  type NodeKind, type Port, type FunctionDef, type ContractKind,
  NODE_WIDTH, nodeHeight, outPort, inPort, emptyGraph,
} from './ir'

// ������ Public API ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

export function parseIgSource(src: string, filePath = ''): BpGraph {
  const lines = src.split('\n')
  const graph = emptyGraph(filePath)

  let i = 0

  while (i < lines.length) {
    const line = lines[i]
    const trimmed = line.trim()

    if (!trimmed || trimmed.startsWith('--')) { i++; continue }

    // module declaration
    if (trimmed.startsWith('module ')) {
      graph.moduleDecl = trimmed.slice(7).trim()
      i++; continue
    }

    // import (single or multi-line)
    if (trimmed.startsWith('import ')) {
      const { text, next } = collectBlock(lines, i, '{', '}')
      graph.imports.push(text.trim())
      i = next; continue
    }

    // def function (single or multi-line signature + optional body)
    if (trimmed.startsWith('def ')) {
      const def = parseDef(lines, i)
      graph.defs.push(def)
      i = skipDefBody(lines, i); continue
    }

    // observed contract / contract / pipeline
    const contractMatch = trimmed.match(/^(observed\s+)?(?:(contract)|(pipeline))\s+(\w+)/)
    if (contractMatch) {
      const [contract, nextI] = parseContract(lines, i)
      graph.contracts.push(contract)
      i = nextI; continue
    }

    i++
  }

  return graph
}

// ������ Contract / Pipeline parsing ���������������������������������������������������������������������������������������������������������������������������������������������

function parseContract(lines: string[], startI: number): [BpContract, number] {
  const headerLine = lines[startI].trim()
  const observed = headerLine.startsWith('observed')
  const isPipeline = headerLine.includes('pipeline')
  const nameMatch = headerLine.match(/(?:contract|pipeline)\s+(\w+)/)
  const contractName = nameMatch?.[1] ?? 'Unknown'

  const kind: ContractKind = isPipeline ? 'pipeline'
    : observed ? 'observed_contract' : 'contract'

  // find the opening brace and collect body lines
  let bodyStart = startI
  while (bodyStart < lines.length && !lines[bodyStart].includes('{')) bodyStart++

  const bodyLines: Array<{ text: string; lineNo: number }> = []
  let depth = 0
  let i = bodyStart
  while (i < lines.length) {
    const ch = lines[i]
    for (const c of ch) { if (c === '{') depth++; if (c === '}') depth-- }
    bodyLines.push({ text: lines[i], lineNo: i + 1 })
    if (depth === 0 && i > bodyStart) { i++; break }
    i++
  }

  const nodes: BpNode[] = []
  const nodeNames = new Set<string>()
  const rawDeps: Map<string, string[]> = new Map()  // nodeId ��� depNames
  const currentBlocks: string[] = []

  // Parse body lines for node declarations
  let lineIdx = 0
  while (lineIdx < bodyLines.length) {
    const { text, lineNo } = bodyLines[lineIdx]
    const t = text.trim()
    if (!t || t.startsWith('--')) { lineIdx++; continue }

    if (lineIdx > 0 && lineIdx < bodyLines.length - 1) {
      const closeCount = (t.match(/\}/g) || []).length
      for (let c = 0; c < closeCount; c++) {
        currentBlocks.pop()
      }
    }

    const prefix = currentBlocks.length > 0 ? currentBlocks.join('::') : undefined

    if (t.startsWith('invariant ')) {
      const remainingLines = bodyLines.slice(lineIdx).map(bl => bl.text)
      const [node, consumed] = parseInvariantBlock(remainingLines, 0, contractName)
      node.sourceLine = lineNo
      if (prefix) {
        node.id = `${contractName}__${prefix}__${node.kind}__${node.name}`
      }

      const deps = node.props.predicate ? [node.props.predicate] : []
      rawDeps.set(node.id, deps)
      nodeNames.add(node.name)
      nodes.push(node)

      lineIdx += consumed
      continue
    }

    const node = parseBodyLine(t, contractName, lineNo, prefix)
    if (node) {
      // Compute deps from the 'expr' prop.
      // For output/snapshot: also depend on any compute/read with the same name.
      // For loop: depend on the collection node.
      let expr = node.props.expr ?? ''
      if ((node.kind === 'output' || node.kind === 'snapshot') && !expr) {
        expr = node.name   // "output x" implicitly references compute/read named x
      }
      if (node.kind === 'loop' && node.props.over) {
        expr = (expr + ' ' + node.props.over).trim()
      }
      const deps = extractDeps(expr, nodeNames)
      rawDeps.set(node.id, deps)
      nodeNames.add(node.name)
      nodes.push(node)

      if (node.kind === 'loop' || node.kind === 'window') {
        currentBlocks.push(node.name)
      }
    }
    lineIdx++
  }

  // Build edges from rawDeps (after all nodes known)
  const edges: BpEdge[] = buildEdges(nodes, rawDeps)

  // Wire input ports on compute/output/snapshot nodes from edges
  wireInPorts(nodes, edges)

  // Compute heights
  for (const n of nodes) { n.height = nodeHeight(n) }

  const contract: BpContract = {
    id:      contractName,
    name:    contractName,
    kind,
    nodes,
    edges,
    offsetX: 0,
    offsetY: 0,
  }

  return [contract, i]
}

// ������ Body line parsers ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������

type BodyParser = (t: string, contractId: string, line: number) => BpNode | null

const BODY_PARSERS: BodyParser[] = [
  parseInputLine,
  parseComputeLine,
  parseOutputLine,
  parseReadLine,
  parseSnapshotLine,
  parseWindowLine,
  parseLoopLine,
  parseStepLine,
  parseEscapeLine,
]

function parseBodyLine(t: string, contractId: string, line: number, prefix?: string): BpNode | null {
  for (const parser of BODY_PARSERS) {
    const result = parser(t, contractId, line)
    if (result) {
      if (prefix) {
        result.id = `${contractId}__${prefix}__${result.kind}__${result.name}`
      }
      return result
    }
  }
  return null
}

// input name: Type
function parseInputLine(t: string, cid: string, line: number): BpNode | null {
  const m = t.match(/^input\s+(\w+)\s*:\s*(.+)/)
  if (!m) return null
  const [, name, type] = m
  return makeNode(cid, 'input', name, line, [], [outPort('out', type)], { type })
}

// compute name = expr
function parseComputeLine(t: string, cid: string, line: number): BpNode | null {
  const m = t.match(/^compute\s+(\w+)\s*=\s*(.+)/)
  if (!m) return null
  const [, name, expr] = m
  return makeNode(cid, 'compute', name, line, [], [outPort('out')], { expr: expr.trim() })
}

// output name: Type [lifecycle ...]
function parseOutputLine(t: string, cid: string, line: number): BpNode | null {
  const m = t.match(/^output\s+(\w+)\s*:\s*(\S+)(?:\s+lifecycle\s+(\S+))?/)
  if (!m) return null
  const [, name, type, lifecycle] = m
  const props: Record<string, string> = { type }
  if (lifecycle) props.lifecycle = lifecycle
  return makeNode(cid, 'output', name, line, [inPort(name, type)], [], props)
}

// read name: Type \n  from "path" \n  lifecycle :durable
function parseReadLine(t: string, cid: string, line: number): BpNode | null {
  const m = t.match(/^read\s+(\w+)\s*:\s*(.+)/)
  if (!m) return null
  const [, name, type] = m
  return makeNode(cid, 'read', name, line, [], [outPort('out', type)], { type })
}

// snapshot name = expr [lifecycle :durable]  |  snapshot name lifecycle :durable
function parseSnapshotLine(t: string, cid: string, line: number): BpNode | null {
  if (!t.startsWith('snapshot ')) return null
  const nameMatch = t.match(/^snapshot\s+(\w+)/)
  if (!nameMatch) return null
  const [, name] = nameMatch
  // Extract optional expr (between = and lifecycle, or end of line)
  const exprMatch = t.match(/=\s*(.+?)(?:\s+lifecycle\s|\s*$)/)
  const lifecycleMatch = t.match(/lifecycle\s+(\S+)/)
  const props: Record<string, string> = {}
  if (exprMatch?.[1]?.trim()) props.expr = exprMatch[1].trim()
  if (lifecycleMatch?.[1])     props.lifecycle = lifecycleMatch[1]
  return makeNode(cid, 'snapshot', name, line, [inPort(name)], [], props)
}

// window "label" {
function parseWindowLine(t: string, cid: string, line: number): BpNode | null {
  const m = t.match(/^window\s+"([^"]+)"/)
  if (!m) return null
  return makeNode(cid, 'window', m[1], line, [], [], {})
}

// loop Name in items max_steps: N
function parseLoopLine(t: string, cid: string, line: number): BpNode | null {
  const m = t.match(/^loop\s+(\w+)\s+in\s+(\w+)/)
  if (!m) return null
  const [, loopName, collection] = m
  return makeNode(cid, 'loop', loopName, line, [inPort(collection)], [], { over: collection })
}

// step name: function
function parseStepLine(t: string, cid: string, line: number): BpNode | null {
  const m = t.match(/^step\s+(\w+)\s*:\s*(\S+)/)
  if (!m) return null
  const [, name, fn] = m
  return makeNode(cid, 'step', name, line, [inPort('in')], [outPort('out')], { fn })
}

// escape keyword
function parseEscapeLine(t: string, cid: string, line: number): BpNode | null {
  const m = t.match(/^escape\s+(\w+)/)
  if (!m) return null
  return makeNode(cid, 'escape', m[1], line, [], [], {})
}

// ������ Edge inference ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

/**
 * Extract referenced node names from an expression.
 * Strategy: scan for identifiers that match known node names.
 */
function extractDeps(expr: string, knownNames: Set<string>): string[] {
  if (!expr) return []
  // extract all word tokens from the expression
  const tokens = expr.match(/\b[a-z_]\w*\b/g) ?? []
  return [...new Set(tokens.filter(t => knownNames.has(t)))]
}

// Source-preference for name resolution: compute > read > input > snapshot > others
const SOURCE_KIND_PRIORITY: Record<string, number> = {
  input: 4, read: 3, compute: 2, snapshot: 1, loop: 1, step: 1,
}

function buildEdges(nodes: BpNode[], rawDeps: Map<string, string[]>): BpEdge[] {
  const edges: BpEdge[] = []

  // Build name���id map preferring source nodes (compute/read/input over output)
  const nameToId = new Map<string, string>()
  for (const n of nodes) {
    const priority = SOURCE_KIND_PRIORITY[n.kind] ?? 0
    const existing = nameToId.get(n.name)
    if (!existing) {
      nameToId.set(n.name, n.id)
    } else {
      // Keep the one with higher source priority
      const existingNode = nodes.find(x => x.id === existing)
      const existingPriority = SOURCE_KIND_PRIORITY[existingNode?.kind ?? ''] ?? 0
      if (priority > existingPriority) nameToId.set(n.name, n.id)
    }
  }

  for (const [toId, deps] of rawDeps) {
    for (const dep of deps) {
      const fromId = nameToId.get(dep)
      if (!fromId || fromId === toId) continue
      const edgeId = `${fromId}���${toId}:${dep}`
      if (edges.some(e => e.id === edgeId)) continue  // deduplicate
      edges.push({
        id:         edgeId,
        fromNodeId: fromId,
        fromPort:   'out',
        toNodeId:   toId,
        toPort:     `in:${dep}`,
      })
    }
  }

  return edges
}

/** Add inPorts to compute/output/snapshot nodes based on incoming edges */
function wireInPorts(nodes: BpNode[], edges: BpEdge[]) {
  const nodeMap = new Map(nodes.map(n => [n.id, n]))
  for (const edge of edges) {
    const toNode = nodeMap.get(edge.toNodeId)
    if (!toNode) continue
    const portLabel = edge.fromPort === 'out'
      ? edge.toPort.replace('in:', '')
      : edge.toPort
    // avoid duplicate ports
    if (!toNode.inPorts.some(p => p.id === edge.toPort)) {
      toNode.inPorts.push(inPort(portLabel))
    }
  }
}

// ������ Helper: node factory ������������������������������������������������������������������������������������������������������������������������������������������������������������������

function makeNode(
  contractId: string,
  kind: NodeKind,
  name: string,
  sourceLine: number,
  inPorts: Port[],
  outPorts: Port[],
  props: Record<string, string>,
): BpNode {
  // Include kind in ID to avoid collisions when output and compute share a name
  return {
    id: `${contractId}__${kind}__${name}`,
    kind, name, sourceLine,
    x: 0, y: 0,
    width: NODE_WIDTH,
    height: 0,   // computed later after wireInPorts
    inPorts, outPorts, props,
  }
}

// ������ Def parsing ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

function parseDef(lines: string[], startI: number): FunctionDef {
  const line = lines[startI]
  const nameMatch = line.match(/def\s+(\w+)/)
  const name = nameMatch?.[1] ?? 'unknown'
  return { name, signature: line.trim(), line: startI + 1 }
}

function skipDefBody(lines: string[], startI: number): number {
  // If line contains '{', skip until matching '}'
  let depth = 0
  let i = startI
  while (i < lines.length) {
    for (const c of lines[i]) {
      if (c === '{') depth++
      if (c === '}') depth--
    }
    i++
    if (depth === 0) break
  }
  return i
}

// ������ Invariant block parsing ���������������������������������������������������������������������������������������������������������������������������������������������������������

function parseInvariantBlock(lines: string[], startI: number, cid: string): [BpNode, number] {
  const headerLine = lines[startI].trim()
  const m = headerLine.match(/^invariant\s+(\w+)/)
  const name = m?.[1] ?? 'unknown'
  const lineNo = startI + 1

  const props: Record<string, string> = {}
  let i = startI
  let depth = 0
  let hasBraces = false

  if (headerLine.includes('{')) {
    hasBraces = true
    depth = 1
  }

  i++ // move past header line

  while (i < lines.length) {
    const rawLine = lines[i]
    const t = rawLine.trim()
    if (!t || t.startsWith('--')) {
      i++
      continue
    }

    if (!hasBraces && t === '{') {
      hasBraces = true
      depth = 1
      i++
      continue
    }

    for (const c of rawLine) {
      if (c === '{') {
        hasBraces = true
        depth++
      }
      if (c === '}') {
        depth--
      }
    }

    const predMatch = t.match(/^predicate\s*:\s*(\w+)/)
    if (predMatch) props.predicate = predMatch[1]

    const sevMatch = t.match(/^severity\s*:\s*:?(\w+)/)
    if (sevMatch) props.severity = sevMatch[1]

    const labelMatch = t.match(/^label\s*:\s*"([^"]+)"/)
    if (labelMatch) props.label = labelMatch[1]

    const msgMatch = t.match(/^message\s*:\s*"([^"]+)"/)
    if (msgMatch) props.message = msgMatch[1]

    const overridableMatch = t.match(/^overridable_with\s*:\s*:?(\w+)/)
    if (overridableMatch) props.overridable_with = overridableMatch[1]

    if (hasBraces) {
      if (depth === 0) {
        i++
        break
      }
    } else {
      const isAttributeLine = t.includes(':') && (
        t.startsWith('predicate') ||
        t.startsWith('severity') ||
        t.startsWith('label') ||
        t.startsWith('message') ||
        t.startsWith('overridable_with')
      )
      if (!isAttributeLine) {
        break
      }
    }
    i++
  }

  const inPorts = props.predicate ? [inPort(props.predicate)] : []

  const node = makeNode(cid, 'invariant', name, lineNo, inPorts, [], props)
  if (props.predicate) {
    node.props.expr = props.predicate
  }
  return [node, i - startI]
}

// ������ Utility: collect multi-line block ���������������������������������������������������������������������������������������������������������������������������

function collectBlock(
  lines: string[], startI: number,
  open: string, close: string,
): { text: string; next: number } {
  let text = lines[startI]
  let i = startI + 1
  if (!text.includes(open)) return { text, next: i }
  while (i < lines.length && !text.includes(close)) {
    text += ' ' + lines[i].trim()
    i++
  }
  return { text, next: i }
}
