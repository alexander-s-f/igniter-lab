package com.igniter.plugin

import com.igniter.plugin.compiler.IgniterDiagnosticMapper
import com.igniter.plugin.compiler.IgniterProjectModePlanner
import com.igniter.plugin.compiler.IgniterReportParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * End-to-end proof for project-mode diagnostic mapping
 * (card LAB-JETBRAINS-PROJECT-MODE-DIAGNOSTIC-MAPPING-P9) against the LIVE
 * `igniter_compiler`. Drives the exact plugin chain: project-mode compile →
 * [IgniterReportParser] (diagnostics + `source_line_map`) → [IgniterDiagnosticMapper]
 * (attribute to the current file, remap to original line, drop other-file diags).
 */
class IgniterProjectModeDiagnosticMappingProofTest {

    private fun resolveBinary(): File? {
        System.getenv("IGNITER_COMPILER")?.let { File(it).takeIf { f -> f.canExecute() }?.let { return it } }
        System.getenv("IGNITER_LAB_HOME")?.let { home ->
            for (p in listOf("release", "debug")) {
                val f = File(home, "igniter-compiler/target/$p/igniter_compiler")
                if (f.canExecute()) return f
            }
        }
        for (p in listOf("release", "debug")) {
            val f = File("../igniter-compiler/target/$p/igniter_compiler")
            if (f.canExecute()) return f.absoluteFile
        }
        return null
    }

    /** A two-file project: valid types.ig + a webhook.ig with [webhookBody]. */
    private fun project(webhookBody: String): File {
        val root = Files.createTempDirectory("p9_proof").toFile()
        File(root, "types.ig").writeText("module P9.Types\n\ntype Rec {\n  a : Integer\n}\n")
        File(root, "webhook.ig").writeText(webhookBody)
        return root
    }

    /** Run project mode and return the raw compilation_report.json text. */
    private fun compileProjectReport(binary: File, root: File, entry: String, currentFile: File): String {
        val out = File(root, "out")
        val igapp = File(out, "${currentFile.nameWithoutExtension}.igapp")
        val cmd = IgniterProjectModePlanner.buildCompileArgs(
            binary.absolutePath, root.absolutePath, entry,
            currentFile.absolutePath, currentFile.absolutePath, igapp.absolutePath
        )
        ProcessBuilder(cmd).redirectErrorStream(true).start().apply { inputStream.readBytes(); waitFor() }
        val inside = File(igapp, "compilation_report.json")
        val sibling = File(out, "${currentFile.nameWithoutExtension}.compilation_report.json")
        return listOf(inside, sibling).firstOrNull { it.exists() }?.readText() ?: ""
    }

    @Test fun `current-file parse error is attributed and remapped to its original line`() {
        val binary = resolveBinary()
        assumeTrue("igniter_compiler not built — skipping live proof", binary != null)

        // Parse error on original line 5 of webhook.ig.
        val root = project(
            "module P9.Webhook\nimport P9.Types.{ Rec }\n\npure contract C {\n  input @@@ bad\n  output v : Integer\n}\n"
        )
        val webhook = File(root, "webhook.ig")
        val report = compileProjectReport(binary!!, root, "P9.Webhook", webhook)

        val diags = IgniterReportParser.parseReport(report)
        val map = IgniterReportParser.parseSourceLineMap(report)
        val mapped = IgniterDiagnosticMapper.remapForCurrentFile(diags, map, setOf(webhook.absolutePath))

        assertTrue("a diagnostic should be attributed to the current file", mapped.isNotEmpty())
        // Remapped to the original webhook line (5), not the merged universe line.
        assertTrue("diagnostic remapped to original line 5, got ${mapped.map { it.line }}",
            mapped.any { it.line == 5 })
    }

    @Test fun `imported-file parse error is dropped from the current editor`() {
        val binary = resolveBinary()
        assumeTrue("igniter_compiler not built — skipping live proof", binary != null)

        // webhook.ig is valid and imports types; the PARSE ERROR is in types.ig.
        val root = Files.createTempDirectory("p9_proof_imp").toFile()
        File(root, "types.ig").writeText("module P9.Types\n\ntype Rec {\n  @@@ bad\n}\n")
        val webhook = File(root, "webhook.ig").apply {
            writeText("module P9.Webhook\nimport P9.Types.{ Rec }\n\npure contract C {\n  input r : Rec\n  compute v : Integer = r.a\n  output v : Integer\n}\n")
        }
        val report = compileProjectReport(binary!!, root, "P9.Webhook", webhook)

        val diags = IgniterReportParser.parseReport(report)
        val map = IgniterReportParser.parseSourceLineMap(report)
        // There IS a compiler diagnostic (the types.ig parse error)...
        assumeTrue("expected a compiler diagnostic to map", diags.isNotEmpty() && map.isNotEmpty())
        val mapped = IgniterDiagnosticMapper.remapForCurrentFile(diags, map, setOf(webhook.absolutePath))
        // ...but it belongs to types.ig, so it must NOT annotate the open webhook.ig.
        assertEquals("imported-file diagnostics must not annotate the current editor",
            emptyList<Int>(), mapped.map { it.line })
    }
}
