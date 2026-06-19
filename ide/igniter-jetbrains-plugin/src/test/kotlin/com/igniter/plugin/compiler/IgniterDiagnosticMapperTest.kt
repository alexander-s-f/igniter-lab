package com.igniter.plugin.compiler

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

/**
 * Pure tests for project-mode diagnostic mapping
 * (card LAB-JETBRAINS-PROJECT-MODE-DIAGNOSTIC-MAPPING-P9): attributing merged
 * diagnostics to the current file, remapping to original lines, dropping
 * other-file diagnostics, and keeping unattributable ones. Also covers the
 * report parser's `source_line_map` + per-diagnostic enrichment extraction.
 */
class IgniterDiagnosticMapperTest {

    // Real temp files so canonical-path normalization is stable across the test.
    private val dir = Files.createTempDirectory("p9").toFile()
    private val webhook = java.io.File(dir, "webhook.ig").apply { writeText("module W\n") }.absolutePath
    private val types = java.io.File(dir, "types.ig").apply { writeText("module T\n") }.absolutePath

    private fun diag(
        code: String = "OOF-P1",
        line: Int = 1,
        sourcePath: String? = null,
        originalLine: Int? = null,
        mergedLine: Int? = null
    ) = OofDiagnostic(code, "msg", line, 1, OofSeverity.ERROR, sourcePath, originalLine, mergedLine)

    // ── Mapper ──────────────────────────────────────────────────────────────

    @Test fun `enriched diagnostic for current file is remapped to its original line`() {
        val d = diag(line = 11, sourcePath = webhook, originalLine = 5, mergedLine = 11)
        val out = IgniterDiagnosticMapper.remapForCurrentFile(listOf(d), emptyList(), setOf(webhook))
        assertEquals(1, out.size)
        assertEquals(5, out[0].line)          // remapped merged 11 -> original 5
    }

    @Test fun `enriched diagnostic for a different file is dropped`() {
        val d = diag(line = 11, sourcePath = types, originalLine = 5, mergedLine = 11)
        val out = IgniterDiagnosticMapper.remapForCurrentFile(listOf(d), emptyList(), setOf(webhook))
        assertTrue("imported-file diagnostic must not annotate the current editor", out.isEmpty())
    }

    @Test fun `merged-line-only diagnostic is attributed via the source line map`() {
        // No per-diagnostic enrichment; origin resolved through the line map.
        val d = diag(line = 11, sourcePath = null, originalLine = null, mergedLine = 11)
        val map = listOf(SourceLineMapEntry(11, webhook, "W", 6))
        val out = IgniterDiagnosticMapper.remapForCurrentFile(listOf(d), map, setOf(webhook))
        assertEquals(1, out.size)
        assertEquals(6, out[0].line)
    }

    @Test fun `merged-line-only diagnostic for another file is dropped via the map`() {
        val d = diag(line = 11, mergedLine = 11)
        val map = listOf(SourceLineMapEntry(11, types, "T", 6))
        val out = IgniterDiagnosticMapper.remapForCurrentFile(listOf(d), map, setOf(webhook))
        assertTrue(out.isEmpty())
    }

    @Test fun `unattributable diagnostic (null line) is kept unchanged`() {
        // The typecheck OOF-P1 case: line:null, no enrichment, not in the map.
        val d = diag(line = 1, sourcePath = null, originalLine = null, mergedLine = null)
        val out = IgniterDiagnosticMapper.remapForCurrentFile(listOf(d), emptyList(), setOf(webhook))
        assertEquals(1, out.size)
        assertEquals(d, out[0])               // unchanged — never silently dropped
    }

    @Test fun `empty diagnostics yields empty`() {
        assertTrue(IgniterDiagnosticMapper.remapForCurrentFile(emptyList(), emptyList(), setOf(webhook)).isEmpty())
    }

    // ── Parser: source_line_map + enrichment extraction ─────────────────────

    @Test fun `parseSourceLineMap reads entries`() {
        val json = """
            { "diagnostics": [],
              "source_line_map": [
                { "merged_line": 11, "source_path": "/p/b.ig", "module_path": "Map.B", "original_line": 5 },
                { "merged_line": 12, "source_path": "/p/b.ig", "module_path": "Map.B", "original_line": 6 }
              ] }
        """.trimIndent()
        val map = IgniterReportParser.parseSourceLineMap(json)
        assertEquals(2, map.size)
        assertEquals(SourceLineMapEntry(11, "/p/b.ig", "Map.B", 5), map[0])
    }

    @Test fun `parseReport extracts per-diagnostic origin enrichment`() {
        val json = """
            { "diagnostics": [
                { "rule": "OOF-P1", "severity": "error", "message": "bad",
                  "line": 11, "source_path": "/p/b.ig", "module_path": "Map.B", "original_line": 5 }
              ] }
        """.trimIndent()
        val d = IgniterReportParser.parseReport(json).single()
        assertEquals("/p/b.ig", d.sourcePath)
        assertEquals(5, d.originalLine)
        assertEquals(11, d.mergedLine)
    }

    @Test fun `parseReport leaves origin null for a line-null typecheck diagnostic`() {
        val json = """
            { "diagnostics": [
                { "rule": "OOF-P1", "severity": "error", "message": "Unresolved field", "line": null }
              ] }
        """.trimIndent()
        val d = IgniterReportParser.parseReport(json).single()
        assertNull(d.sourcePath)
        assertNull(d.originalLine)
        assertNull(d.mergedLine)
    }

    @Test fun `single-file report has no source line map`() {
        assertTrue(IgniterReportParser.parseSourceLineMap("""{ "diagnostics": [] }""").isEmpty())
    }
}
