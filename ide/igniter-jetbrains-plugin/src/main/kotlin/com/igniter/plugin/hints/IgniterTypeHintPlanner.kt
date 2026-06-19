package com.igniter.plugin.hints

import com.igniter.plugin.model.IgniterModel

/** A single planned inlay hint: where (1-based [line]) and what ([text], e.g. ": Integer"). */
data class PlannedHint(val nodeId: String, val line: Int, val text: String)

/**
 * Pure (IntelliJ-free) policy that turns a compiler-backed [IgniterModel] into a
 * deterministic list of type inlay hints. Card LAB-JETBRAINS-INLAY-TYPE-HINTS-P2.
 *
 * v0 policy: hint inferred types only for `compute` nodes — their type never
 * appears in source (`compute name = expr`). Explicit `input/output ... : Type`
 * declarations already show the type, so they are not hinted (no duplication).
 * Fail-closed: nodes with `type == null` or unknown line produce no hint.
 */
internal object IgniterTypeHintPlanner {

    fun plan(model: IgniterModel): List<PlannedHint> {
        if (model.isEmpty) return emptyList()
        return model.symbols
            .filter { it.kind == "compute" && it.line > 0 && it.type != null }
            .sortedWith(compareBy({ it.line }, { it.nodeId }))   // deterministic order
            .map { PlannedHint(it.nodeId, it.line, ": ${it.type!!.render()}") }
    }
}
