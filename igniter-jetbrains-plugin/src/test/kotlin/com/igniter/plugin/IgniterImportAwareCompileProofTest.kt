package com.igniter.plugin

import com.igniter.plugin.compiler.IgniterProjectModePlanner
import com.igniter.plugin.compiler.IgniterReportParser
import com.igniter.plugin.compiler.OofDiagnostic
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * End-to-end proof for project-mode delegation (card
 * LAB-JETBRAINS-PROJECT-MODE-DELEGATION-P7) against the LIVE `igniter_compiler`.
 * Skipped (Assume) when the binary is not built.
 *
 * Mirrors the real plugin path: the compiler owns project assembly — the plugin
 * invokes the exact project-mode + overlay command built by
 * [IgniterProjectModePlanner.buildCompileArgs] (`compile --project-root R --entry M
 * --overlay onDisk=buffer --out OUT.igapp`). No plugin-side import graph scanning.
 */
class IgniterImportAwareCompileProofTest {

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

    private fun fixturesDir(): File =
        File(javaClass.classLoader.getResource("fixtures/import_aware/webhook.ig")!!.toURI()).parentFile

    private fun webhook() = File(fixturesDir(), "webhook.ig")

    /** Run `compile <current> --out <out>` (single-file) and return parsed diagnostics. */
    private fun compileSingle(binary: File, current: File, outDir: File): List<OofDiagnostic> {
        val igapp = File(outDir, "${current.nameWithoutExtension}.igapp")
        val cmd = listOf(binary.absolutePath, "compile", current.absolutePath, "--out", igapp.absolutePath)
        ProcessBuilder(cmd).redirectErrorStream(true).start().apply { inputStream.readBytes(); waitFor() }
        return readReport(igapp, outDir, current.nameWithoutExtension)
    }

    /**
     * Run the exact project-mode + overlay command the plugin issues and return
     * parsed diagnostics. Uses [IgniterProjectModePlanner.buildCompileArgs] so the
     * invocation shape is proven against the live binary.
     */
    private fun compileProject(
        binary: File,
        projectRoot: File,
        entry: String,
        overlayOriginal: File,
        overlayBuffer: File,
        outDir: File,
        base: String,
    ): List<OofDiagnostic> {
        val igapp = File(outDir, "$base.igapp")
        val cmd = IgniterProjectModePlanner.buildCompileArgs(
            binary = binary.absolutePath,
            projectRoot = projectRoot.absolutePath,
            entryModule = entry,
            overlayOriginal = overlayOriginal.absolutePath,
            overlayBuffer = overlayBuffer.absolutePath,
            outIgapp = igapp.absolutePath,
        )
        ProcessBuilder(cmd).redirectErrorStream(true).start().apply { inputStream.readBytes(); waitFor() }
        return readReport(igapp, outDir, base)
    }

    private fun readReport(igapp: File, outDir: File, base: String): List<OofDiagnostic> {
        val inside = File(igapp, "compilation_report.json")
        val sibling = File(outDir, "$base.compilation_report.json")
        val report = listOf(inside, sibling).firstOrNull { it.exists() } ?: return emptyList()
        return IgniterReportParser.parseReport(report.readText())
    }

    private fun unresolvedFieldDiags(diags: List<OofDiagnostic>) =
        diags.filter { it.code == "OOF-P1" && it.message.contains("Unresolved field") }

    @Test fun `baseline - current file alone reproduces the false OOF-P1`() {
        val binary = resolveBinary()
        assumeTrue("igniter_compiler not built — skipping live proof", binary != null)

        val out = Files.createTempDirectory("igniter_p7_single").toFile()
        val diags = compileSingle(binary!!, webhook(), out)

        // The documented bug: compiling the importing file alone loses CallrailCall.
        assertTrue("single-file compile must show the false unresolved-field diagnostics",
            unresolvedFieldDiags(diags).isNotEmpty())
    }

    @Test fun `project mode plus overlay compiles without false OOF-P1 (acceptance 3)`() {
        val binary = resolveBinary()
        assumeTrue("igniter_compiler not built — skipping live proof", binary != null)

        val text = webhook().readText()
        val entry = IgniterProjectModePlanner.entryModuleForProjectMode(text)
        assertEquals("project mode must apply to the importing webhook", "CallRouterWebhook", entry)

        val out = Files.createTempDirectory("igniter_p7_project").toFile()
        // Project root = the fixtures dir (contains webhook.ig + types.ig); the saved
        // file is its own overlay buffer (content == disk).
        val diags = compileProject(
            binary!!, fixturesDir(), entry!!, webhook(), webhook(), out, "webhook"
        )

        assertTrue("project-mode compile must have NO false unresolved-field diagnostics, got: " +
            unresolvedFieldDiags(diags).map { it.message }, unresolvedFieldDiags(diags).isEmpty())
    }

    @Test fun `overlay buffer text wins over disk for the current file (acceptance 2)`() {
        val binary = resolveBinary()
        assumeTrue("igniter_compiler not built — skipping live proof", binary != null)

        // On-disk webhook is valid; the overlay buffer introduces a bad field. The
        // diagnostics must reflect the BUFFER, proving overlay text wins.
        val tmp = Files.createTempDirectory("igniter_p7_overlay").toFile()
        val root = File(tmp, "proj").apply { mkdirs() }
        File(root, "types.ig").writeText(File(fixturesDir(), "types.ig").readText())
        val onDisk = File(root, "webhook.ig").apply { writeText(webhook().readText()) }
        val buffer = File(tmp, "buffer.ig").apply {
            writeText(
                "module CallRouterWebhook\n" +
                "import CallRouterTypes\n\n" +
                "pure contract M {\n  input call : CallrailCall\n" +
                "  compute x = call.nonexistent_field\n  output x : String\n}\n"
            )
        }
        val diags = compileProject(
            binary!!, root, "CallRouterWebhook", onDisk, buffer, File(tmp, "out"), "webhook"
        )
        assertTrue("overlay buffer's bad field must surface (overlay text wins), got: " +
            diags.map { it.code + " " + it.message },
            unresolvedFieldDiags(diags).isNotEmpty())
    }

    @Test fun `stdlib imports do not require a project file`() {
        // The webhook fixture imports stdlib.collection.{ count }; it is filtered
        // out of the modules project mode treats as project dependencies.
        val imports = IgniterProjectModePlanner.importedModules(webhook().readText())
        assertFalse("stdlib imports must not be treated as project modules",
            imports.any { IgniterProjectModePlanner.isStdlib(it) })
        assertEquals(listOf("CallRouterTypes"), imports)
    }

    @Test fun `missing-only non-stdlib import yields compiler-authoritative OOF-IMP (acceptance 4)`() {
        val binary = resolveBinary()
        assumeTrue("igniter_compiler not built — skipping live proof", binary != null)

        // The P7 improvement over P6: even when NOTHING resolves on disk, project
        // mode still reports the dangling import (P6 fell back to single-file and
        // missed it).
        val root = Files.createTempDirectory("igniter_p7_missing").toFile()
        val current = File(root, "consumer.ig").apply {
            writeText(
                "module ConsumerMod\n" +
                "import TotallyMissingModule.{ Nope }\n\n" +
                "pure contract C {\n  input n : Integer\n  compute v : Integer = n\n  output v : Integer\n}\n"
            )
        }
        val diags = compileProject(
            binary!!, root, "ConsumerMod", current, current, File(root, "out"), "consumer"
        )
        assertTrue("missing import must surface as a compiler OOF-IMP* diagnostic, got: " +
            diags.map { it.code + " " + it.message },
            diags.any { it.code.startsWith("OOF-IMP") })
    }
}
