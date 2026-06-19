/**
 * layout.ts ��� Auto-layout algorithm for Blueprint graphs.
 *
 * Pure function: takes a BpGraph, returns a new BpGraph with x/y assigned.
 * Extensibility: add new layout strategies as exported functions.
 *
 * Current strategy: column layout (topological sort ��� assign to columns).
 * Future strategies: force-directed, ELK, dagre, etc.
 */

import type { BpGraph, BpContract, BpNode, BpEdge } from './ir'

// ������ Layout constants ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

const COL_GAP   = 260    // horizontal distance between columns
const ROW_GAP   = 24     // vertical gap between nodes in same column
const START_X   = 60     // leftmost column x
const START_Y   = 60     // top padding
const CONTRACT_GAP = 80  // vertical gap between contracts in multi-contract files

// ������ Public API ������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

/**
 * Assign x/y to all nodes using column layout.
 * Returns a new graph (does not mutate the input).
 */
export function applyLayout(graph: BpGraph): BpGraph {
  let yOffset = 0
  const contracts = graph.contracts.map(contract => {
    const laid = layoutContract(contract, 0, yOffset)
    yOffset += contractHeight(laid) + CONTRACT_GAP
    return laid
  })
  return { ...graph, contracts }
}

// ������ Column layout for a single contract ������������������������������������������������������������������������������������������������������������������

function layoutContract(contract: BpContract, baseX: number, baseY: number): BpContract {
  const columns = assignColumns(contract.nodes, contract.edges)
  const nodes   = positionNodes(contract.nodes, columns, baseX + START_X, baseY + START_Y)
  return { ...contract, nodes, offsetX: baseX, offsetY: baseY }
}

/**
 * Assign each node to a column (0 = leftmost).
 * Algorithm: longest path from sources (nodes with no incoming edges).
 *
 * Column order:
 *   0 ��� inputs, reads, escapes
 *   1..N-2 ��� computes, loops, snapshots (topologically sorted)
 *   N-1 ��� outputs, windows
 */
function assignColumns(nodes: BpNode[], edges: BpEdge[]): Map<string, number> {
  const colMap = new Map<string, number>()
  const inDegree = new Map<string, number>()
  const successors = new Map<string, string[]>()   // nodeId ��� [successorIds]

  for (const n of nodes) {
    inDegree.set(n.id, 0)
    successors.set(n.id, [])
  }

  for (const e of edges) {
    inDegree.set(e.toNodeId, (inDegree.get(e.toNodeId) ?? 0) + 1)
    successors.get(e.fromNodeId)?.push(e.toNodeId)
  }

  // Sources: nodes with no incoming edges (or forced-left kinds)
  const LEFT_KINDS  = new Set(['input', 'read', 'escape'])
  const RIGHT_KINDS = new Set(['output', 'window'])

  const queue: string[] = []
  for (const n of nodes) {
    if (LEFT_KINDS.has(n.kind) || inDegree.get(n.id) === 0) {
      colMap.set(n.id, LEFT_KINDS.has(n.kind) ? 0 : 1)
      queue.push(n.id)
    }
  }

  // BFS/Kahn's algorithm for column assignment
  let qi = 0
  while (qi < queue.length) {
    const current = queue[qi++]
    const col = colMap.get(current) ?? 0
    for (const succ of successors.get(current) ?? []) {
      const newCol = Math.max(colMap.get(succ) ?? 0, col + 1)
      colMap.set(succ, newCol)
      const deg = (inDegree.get(succ) ?? 1) - 1
      inDegree.set(succ, deg)
      if (deg === 0) queue.push(succ)
    }
  }

  // Force output/window nodes to the rightmost column + 1
  const maxCol = Math.max(0, ...colMap.values())
  for (const n of nodes) {
    if (RIGHT_KINDS.has(n.kind)) {
      colMap.set(n.id, maxCol + 1)
    }
    // Ensure all nodes are assigned
    if (!colMap.has(n.id)) colMap.set(n.id, maxCol)
  }

  return colMap
}

/**
 * Given column assignments, compute pixel (x, y) for each node.
 * Nodes within a column are stacked vertically sorted by name.
 */
function positionNodes(
  nodes: BpNode[],
  columns: Map<string, number>,
  baseX: number,
  baseY: number,
): BpNode[] {
  // Group nodes by column
  const byCol = new Map<number, BpNode[]>()
  for (const n of nodes) {
    const col = columns.get(n.id) ?? 0
    const arr = byCol.get(col) ?? []
    arr.push(n)
    byCol.set(col, arr)
  }

  // Sort within each column: by kind priority then name
  const KIND_PRIORITY: Record<string, number> = {
    input: 0, read: 1, escape: 2,
    compute: 5, loop: 6, snapshot: 7, window: 8, step: 9,
    output: 10,
  }

  const result: BpNode[] = []
  for (const [col, colNodes] of [...byCol.entries()].sort(([a], [b]) => a - b)) {
    colNodes.sort((a, b) =>
      (KIND_PRIORITY[a.kind] ?? 5) - (KIND_PRIORITY[b.kind] ?? 5) ||
      a.name.localeCompare(b.name)
    )
    let y = baseY
    for (const node of colNodes) {
      result.push({ ...node, x: baseX + col * COL_GAP, y })
      y += node.height + ROW_GAP
    }
  }

  return result
}

// ������ Helpers ���������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������

function contractHeight(contract: BpContract): number {
  if (contract.nodes.length === 0) return 200
  return Math.max(...contract.nodes.map(n => n.y + n.height)) - START_Y
}
