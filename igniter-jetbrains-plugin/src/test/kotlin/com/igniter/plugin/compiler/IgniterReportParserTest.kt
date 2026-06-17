package com.igniter.plugin.compiler

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Proves diagnostic parsing (Card LAB-JETBRAINS-SEMANTIC-NAV-PROOF-P1, check A) against
 * REAL `compilation_report.json` files from the live `igniter_compiler`.
 */
class IgniterReportParserTest {

    private fun resource(path: String): File =
        File(javaClass.classLoader.getResource(path)!!.toURI())

    @Test fun `success report has no diagnostics`() {
        val diags = IgniterReportParser.parseReport(resource("fixtures/add.igapp/compilation_report.json").readText())
        assertTrue(diags.isEmpty())
    }

    @Test fun `refusal report parses rule severity and top-level line`() {
        val diags = IgniterReportParser.parseReport(resource("fixtures/bad.compilation_report.json").readText())
        assertTrue("expected at least one diagnostic", diags.isNotEmpty())
        val first = diags.first()
        assertEquals("OOF-P0", first.code)            // `rule`, not `code`
        assertEquals(OofSeverity.ERROR, first.severity)
        assertEquals(2, first.line)                   // Rust parse error: top-level line
        assertTrue(first.message.isNotBlank())
    }

    @Test fun `span-nested location is read when present`() {
        val json = """{ "diagnostics": [
            { "rule": "OOF-TY0", "severity": "warning", "message": "m", "span": { "line": 12, "col": 5 } }
        ] }"""
        val d = IgniterReportParser.parseReport(json).single()
        assertEquals(12, d.line)
        assertEquals(5, d.col)
        assertEquals(OofSeverity.WARNING, d.severity)
    }

    @Test fun `unparseable input yields no diagnostics rather than throwing`() {
        assertTrue(IgniterReportParser.parseReport("not json").isEmpty())
    }
}
