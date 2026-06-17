package com.igniter.plugin.model

import java.io.File

/** A (possibly parameterized) Igniter type, e.g. `Integer`, `Decimal[2]`, `Collection[Integer]`. */
data class IgniterType(val name: String, val params: List<IgniterType> = emptyList()) {
    fun render(): String =
        if (params.isEmpty()) name
        else "$name[${params.joinToString(", ") { it.render() }}]"
}

/**
 * One declared node of an Igniter program, joined from the compiler's
 * `sourcemap.json` (position + sir_path) and `semantic_ir_program.json`
 * (inferred type + dependency edges).
 *
 * Positions are 1-based as the compiler emits them; 0 means "unknown"
 * (srcmap-v0 tracks start positions only — no end positions yet).
 */
data class SymbolNode(
    val nodeId: String,            // "compute:Add.sum"
    val kind: String,              // contract | input | output | compute | ...
    val name: String,              // "sum"
    val contract: String?,         // "Add"
    val type: IgniterType?,        // inferred type (from SIR), null for contracts
    val line: Int,                 // 1-based start line, 0 if unknown
    val col: Int,                  // 1-based start col, 0 if unknown
    val sirPath: String?,          // JSONPath into semantic_ir_program.json
    val deps: List<String>         // names this node references (compute nodes only)
) {
    val isContract: Boolean get() = kind == "contract"
}

/**
 * Compiler-backed semantic model of a single `.ig` file. Built from the
 * artifacts of one successful compile; [EMPTY] when the file did not compile
 * (callers degrade gracefully rather than guessing).
 *
 * Lab-only convenience view over the compiler's authoritative output — not an
 * independent re-implementation of the language.
 */
class IgniterModel(
    val module: String?,
    val symbols: List<SymbolNode>,
    val igappDir: File?,
    val semanticIrFile: File?,
    val sourceMapFile: File?
) {
    private val byId: Map<String, SymbolNode> = symbols.associateBy { it.nodeId }

    val isEmpty: Boolean get() = symbols.isEmpty()

    fun byNodeId(id: String): SymbolNode? = byId[id]

    /** The declaration whose name token starts exactly at (line, col), if any. */
    fun declarationAt(line: Int, col: Int): SymbolNode? =
        symbols.firstOrNull { it.line == line && it.col == col }

    /** The innermost contract whose declaration starts at or before [line]. */
    fun enclosingContract(line: Int): SymbolNode? =
        symbols.filter { it.isContract && it.line in 1..line }
            .maxByOrNull { it.line }

    /**
     * Resolves a referenced name to its declaration, preferring same-contract
     * value declarations (input/compute) over outputs, then any match.
     */
    fun resolveRef(name: String, contract: String?): SymbolNode? {
        val sameContract = symbols.filter { it.name == name && it.contract == contract }
        return sameContract.firstOrNull { it.kind == "input" || it.kind == "compute" }
            ?: sameContract.firstOrNull()
            ?: symbols.firstOrNull { it.name == name }
    }

    /** Nodes that reference [name] via their dependency edges (find-usages source). */
    fun usagesOf(name: String, contract: String?): List<SymbolNode> =
        symbols.filter { (contract == null || it.contract == contract) && name in it.deps }

    companion object {
        val EMPTY = IgniterModel(null, emptyList(), null, null, null)
    }
}
