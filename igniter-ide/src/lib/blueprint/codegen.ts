/**
 * codegen.ts ��� BpGraph ��� Igniter Lang (.ig) source
 *
 * Pure function: no side effects, no DOM, no Svelte.
 * Extensibility: add entries to NODE_EMITTERS for new node kinds.
 */

import type { BpGraph, BpContract, BpNode, BpEdge } from './ir'

// ������ Public API ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

export function generateIgSource(graph: BpGraph): string {
  const parts: string[] = []

  if (graph.moduleDecl) parts.push(`module ${graph.moduleDecl}`)

  if (graph.imports.length > 0) {
    parts.push('')
    parts.push(...graph.imports.map(imp => `import ${imp}`))
  }

  if (graph.defs.length > 0) {
    parts.push('')
    parts.push(...graph.defs.map(d => d.signature))
  }

  for (const contract of graph.contracts) {
    parts.push('')
    parts.push(emitContract(contract))
  }

  return parts.join('\n')
}

// ������ Contract emitter ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

function emitContract(contract: BpContract): string {
  const header = contract.kind === 'observed_contract'
    ? `observed contract ${contract.name}`
    : contract.kind === 'pipeline'
    ? `pipeline ${contract.name}`
    : `contract ${contract.name}`

  const sortedNodes = topoSort(contract.nodes, contract.edges)
  const body = sortedNodes
    .map(n => '  ' + emitNode(n))
    .filter(Boolean)
    .join('\n')

  return `${header} {\n${body}\n}`
}

// ������ Node emitters (lego: add new kind ��� add entry here) ������������������������������������������������������������������

type NodeEmitter = (node: BpNode) => string

const NODE_EMITTERS: Partial<Record<BpNode['kind'], NodeEmitter>> = {
  input:    emitInput,
  compute:  emitCompute,
  output:   emitOutput,
  read:     emitRead,
  snapshot: emitSnapshot,
  window:   emitWindow,
  loop:     emitLoop,
  step:     emitStep,
  escape:   emitEscape,
}

function emitNode(node: BpNode): string {
  const emitter = NODE_EMITTERS[node.kind]
  return emitter ? emitter(node) : `-- unknown node: ${node.name}`
}

function emitInput(n: BpNode): string {
  const type = n.props.type ?? 'String'
  return `input ${n.name}: ${type}`
}

function emitCompute(n: BpNode): string {
  const expr = n.props.expr ?? n.name
  return `compute ${n.name} = ${expr}`
}

function emitOutput(n: BpNode): string {
  const type      = n.props.type ?? 'String'
  const lifecycle = n.props.lifecycle ? ` lifecycle ${n.props.lifecycle}` : ''
  return `output ${n.name}: ${type}${lifecycle}`
}

function emitRead(n: BpNode): string {
  const type      = n.props.type ?? 'String'
  const from      = n.props.from ?? `"${n.name}"`
  const lifecycle = n.props.lifecycle ?? ':durable'
  return `read ${n.name}: ${type}\n    from ${from}\n    lifecycle ${lifecycle}`
}

function emitSnapshot(n: BpNode): string {
  const lifecycle = n.props.lifecycle ?? ':durable'
  if (n.props.expr) {
    return `snapshot ${n.name} = ${n.props.expr} lifecycle ${lifecycle}`
  }
  return `snapshot ${n.name} lifecycle ${lifecycle}`
}

function emitWindow(n: BpNode): string {
  const kind    = n.props.kind    ?? ':calendar'
  const unit    = n.props.unit    ?? ':day'
  const onClose = n.props.on_close ?? ':snapshot'
  return `window "${n.name}" {\n    kind     ${kind}\n    unit     ${unit}\n    on_close ${onClose}\n  }`
}

function emitLoop(n: BpNode): string {
  const over      = n.props.over ?? 'items'
  const maxSteps  = n.props.max_steps ?? '1000'
  const body      = n.props.body ? `\n    ${n.props.body}\n  ` : '\n    -- loop body\n  '
  return `loop ${n.name} in ${over} max_steps: ${maxSteps} {${body}}`
}

function emitStep(n: BpNode): string {
  const fn = n.props.fn ?? n.name
  return `step ${n.name}: ${fn}`
}

function emitEscape(n: BpNode): string {
  return `escape ${n.name}`
}

// ������ Topological sort for correct emit order ���������������������������������������������������������������������������������������������������������

const EMIT_ORDER_PRIORITY: Record<string, number> = {
  escape:   0,
  input:    1,
  read:     2,
  compute:  3,
  loop:     4,
  snapshot: 5,
  window:   6,
  step:     7,
  output:   8,
}

function topoSort(nodes: BpNode[], edges: BpEdge[]): BpNode[] {
  const inDegree = new Map(nodes.map(n => [n.id, 0]))
  const successors = new Map(nodes.map(n => [n.id, [] as string[]]))

  for (const e of edges) {
    inDegree.set(e.toNodeId, (inDegree.get(e.toNodeId) ?? 0) + 1)
    successors.get(e.fromNodeId)?.push(e.toNodeId)
  }

  const queue = nodes
    .filter(n => inDegree.get(n.id) === 0)
    .sort((a, b) => (EMIT_ORDER_PRIORITY[a.kind] ?? 5) - (EMIT_ORDER_PRIORITY[b.kind] ?? 5))

  const result: BpNode[] = []
  const visited = new Set<string>()

  while (queue.length > 0) {
    // pick next: sort queue by emit priority, then by name
    queue.sort((a, b) =>
      (EMIT_ORDER_PRIORITY[a.kind] ?? 5) - (EMIT_ORDER_PRIORITY[b.kind] ?? 5) ||
      a.name.localeCompare(b.name)
    )
    const node = queue.shift()!
    if (visited.has(node.id)) continue
    visited.add(node.id)
    result.push(node)

    for (const succId of successors.get(node.id) ?? []) {
      const deg = (inDegree.get(succId) ?? 1) - 1
      inDegree.set(succId, deg)
      if (deg === 0) {
        const succNode = nodes.find(n => n.id === succId)
        if (succNode) queue.push(succNode)
      }
    }
  }

  // Append any unreachable nodes at end (shouldn't happen in valid graphs)
  for (const n of nodes) {
    if (!visited.has(n.id)) result.push(n)
  }

  return result
}
