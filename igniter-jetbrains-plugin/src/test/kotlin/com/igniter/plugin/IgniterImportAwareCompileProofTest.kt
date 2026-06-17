package com.igniter.plugin

import com.igniter.plugin.compiler.IgniterImportCompilePlanner
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
 * End-to-end proof for import-aware compilation (card LAB-JETBRAINS-IMPORT-AWARE-COMPILE-P6)
 * against the LIVE `igniter_compiler`. Skipped (Assume) when the binary is not built.
 *
 * Mirrors the real plugin path: parse imports → resolve project module files via
 * [IgniterImportCompilePlanner] → invoke the exact multi-file command the
 * `IgniterCompilerService` issues (`compile <current> <imported…> --out OUT.igapp`).
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

    /** Run `compile <current> <extras…> --out <out>` and return parsed diagnostics. */
    private fun compileDiagnostics(binary: File, current: File, extras: List<File>, outDir: File): List<OofDiagnostic> {
        val igapp = File(outDir, "${current.nameWithoutExtension}.igapp")
        val cmd = listOf(binary.absolutePath, "compile", current.absolutePath) +
            extras.map { it.absolutePath } + listOf("--out", igapp.absolutePath)
        ProcessBuilder(cmd).redirectErrorStream(true).start().apply { inputStream.readBytes(); waitFor() }
        val inside = File(igapp, "compilation_report.json")
        val sibling = File(outDir, "${current.nameWithoutExtension}.compilation_report.json")
        val report = listOf(inside, sibling).firstOrNull { it.exists() } ?: return emptyList()
        return IgniterReportParser.parseReport(report.readText())
    }

    private fun unresolvedFieldDiags(diags: List<OofDiagnostic>) =
        diags.filter { it.code == "OOF-P1" && it.message.contains("Unresolved field") }

    @Test fun `baseline - current file alone reproduces the false OOF-P1 (acceptance 2)`() {
        val binary = resolveBinary()
        assumeTrue("igniter_compiler not built — skipping live proof", binary != null)

        val out = Files.createTempDirectory("igniter_imp_single").toFile()
        val diags = compileDiagnostics(binary!!, webhook(), emptyList(), out)

        // The documented bug: compiling the importing file alone loses CallrailCall.
        assertTrue("single-file compile must show the false unresolved-field diagnostics",
            unresolvedFieldDiags(diags).isNotEmpty())
    }

    @Test fun `import-aware - current plus resolved import compiles without false OOF-P1 (acceptance 1)`() {
        val binary = resolveBinary()
        assumeTrue("igniter_compiler not built — skipping live proof", binary != null)

        val text = webhook().readText()
        // Resolve imported project modules exactly as the plugin does.
        val index = IgniterImportCompilePlanner.scanProject(fixturesDir().toPath(), excludePath = webhook().absolutePath)
        val resolved = IgniterImportCompilePlanner.resolve(
            IgniterImportCompilePlanner.moduleNameOf(text),
            IgniterImportCompilePlanner.importedModules(text),
            index
        ).map(::File)

        // The planner must have found types.ig (the CallRouterTypes module).
        assertTrue("CallRouterTypes must resolve to a project file",
            resolved.any { it.name == "types.ig" })

        val out = Files.createTempDirectory("igniter_imp_multi").toFile()
        val diags = compileDiagnostics(binary!!, webhook(), resolved, out)

        assertTrue("import-aware compile must have NO false unresolved-field diagnostics, got: " +
            unresolvedFieldDiags(diags).map { it.message }, unresolvedFieldDiags(diags).isEmpty())
    }

    @Test fun `stdlib imports do not require a project file (acceptance 3)`() {
        // The webhook fixture imports stdlib.collection.{ count }; it must be filtered
        // out of the modules the planner tries to resolve to files.
        val imports = IgniterImportCompilePlanner.importedModules(webhook().readText())
        assertFalse("stdlib imports must not be resolved to project files",
            imports.any { IgniterImportCompilePlanner.isStdlib(it) })
        assertEquals(listOf("CallRouterTypes"), imports)
    }

    @Test fun `missing non-stdlib import yields compiler-authoritative OOF-IMP (acceptance 4)`() {
        val binary = resolveBinary()
        assumeTrue("igniter_compiler not built — skipping live proof", binary != null)

        val tmp = Files.createTempDirectory("igniter_imp_missing").toFile()
        val types = File(tmp, "types.ig").apply { writeText(File(fixturesDir(), "types.ig").readText()) }
        val current = File(tmp, "consumer.ig").apply {
            writeText(
                "module ConsumerMod\n" +
                "import CallRouterTypes\n" +
                "import TotallyMissingModule\n\n" +
                "pure contract C {\n  input call : CallrailCall\n  compute id = call.id\n  output id : String\n}\n"
            )
        }
        // CallRouterTypes resolves (types.ig); TotallyMissingModule does not → compiler must report it.
        val diags = compileDiagnostics(binary!!, current, listOf(types), File(tmp, "out"))
        assertTrue("missing import must surface as a compiler OOF-IMP* diagnostic, got: " +
            diags.map { it.code + " " + it.message },
            diags.any { it.code.startsWith("OOF-IMP") })
    }
}
