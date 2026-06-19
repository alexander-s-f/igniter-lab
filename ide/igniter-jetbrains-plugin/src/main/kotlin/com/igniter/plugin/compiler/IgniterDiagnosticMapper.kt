package com.igniter.plugin.compiler

import java.io.File

/**
 * One entry of the compiler's multifile/project-mode `source_line_map`
 * (card LAB-COMPILER-MULTIFILE-SOURCE-MAP-P3): a line of the merged
 * `Lab.Multifile.Universe` program traced back to its originating source unit.
 */
data class SourceLineMapEntry(
    val mergedLine: Int,
    val sourcePath: String,
    val modulePath: String,
    val originalLine: Int
)

/**
 * Maps merged/project-mode diagnostics back to the file currently in the editor
 * (card LAB-JETBRAINS-PROJECT-MODE-DIAGNOSTIC-MAPPING-P9).
 *
 * The compiler merges source units into one program, so a project-mode diagnostic
 * may belong to an imported file and/or carry a merged line number. Using the P3
 * per-diagnostic enrichment (`source_path` + `original_line`) — falling back to the
 * `source_line_map` for any diagnostic that only has a merged line — this:
 *
 *  - **remaps** a diagnostic that belongs to the current file to its original line,
 *  - **drops** a diagnostic that belongs to a *different* file (it will be shown
 *    when that file is the active editor), and
 *  - **keeps** a diagnostic whose origin cannot be determined (e.g. a typecheck
 *    `OOF-P1` with `line: null`) unchanged, so nothing is silently lost.
 *
 * This is pure (no IntelliJ) so it is unit-tested directly.
 */
object IgniterDiagnosticMapper {

    /**
     * @param diagnostics the raw project-mode diagnostics (compiler coordinates)
     * @param lineMap the report's `source_line_map`
     * @param currentFileOriginPaths paths that identify the current file's source
     *        unit as the compiler saw it — i.e. the overlay buffer path AND the
     *        on-disk path. Compared by canonical/absolute path.
     */
    fun remapForCurrentFile(
        diagnostics: List<OofDiagnostic>,
        lineMap: List<SourceLineMapEntry>,
        currentFileOriginPaths: Set<String>
    ): List<OofDiagnostic> {
        if (diagnostics.isEmpty()) return diagnostics
        val byMerged = lineMap.associateBy { it.mergedLine }
        val current = currentFileOriginPaths.mapNotNull { normalize(it) }.toSet()

        val out = ArrayList<OofDiagnostic>(diagnostics.size)
        for (d in diagnostics) {
            val origin = originOf(d, byMerged)
            if (origin == null) {
                // Unknown origin (e.g. line:null typecheck) — keep as-is, never drop.
                out += d
                continue
            }
            val (originPath, originLine) = origin
            val normOrigin = normalize(originPath)
            when {
                // Belongs to the current file → remap to its original line.
                normOrigin != null && normOrigin in current ->
                    out += d.copy(line = originLine)
                // Belongs to a different file → not this editor's annotation.
                else -> { /* drop */ }
            }
        }
        return out
    }

    /** Resolve (originPath, originLine): enrichment first, then source_line_map. */
    private fun originOf(d: OofDiagnostic, byMerged: Map<Int, SourceLineMapEntry>): Pair<String, Int>? {
        if (d.sourcePath != null && d.originalLine != null) return d.sourcePath to d.originalLine
        val ml = d.mergedLine ?: return null
        val entry = byMerged[ml] ?: return null
        return entry.sourcePath to entry.originalLine
    }

    private fun normalize(path: String): String? =
        runCatching { File(path).canonicalPath }.getOrElse {
            runCatching { File(path).absolutePath }.getOrNull()
        }
}
