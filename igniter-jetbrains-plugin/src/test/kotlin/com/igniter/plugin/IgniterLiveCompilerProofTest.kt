package com.igniter.plugin

import com.igniter.plugin.compiler.IgniterReportParser
import com.igniter.plugin.model.IgniterModelParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * End-to-end proof against the LIVE `igniter_compiler` (Card check A + the report
 * layouts). Skipped (Assume) when the binary is not resolvable, so the suite stays
 * green in binary-less environments; it runs wherever the lab compiler is built.
 *
 * Invokes the binary directly (the same `compile SOURCE --out OUT.igapp` command the
 * plugin's IgniterCompilerService issues) because that service needs the IntelliJ
 * application; here we exercise the pure parsers on real, freshly-produced artifacts.
 */
class IgniterLiveCompilerProofTest {

    private fun resolveBinary(): File? {
        System.getenv("IGNITER_COMPILER")?.let { File(it).takeIf { f -> f.canExecute() }?.let { return it } }
        System.getenv("IGNITER_LAB_HOME")?.let { home ->
            for (p in listOf("release", "debug")) {
                val f = File(home, "igniter-compiler/target/$p/igniter_compiler")
                if (f.canExecute()) return f
            }
        }
        // Module dir is the gradle test working dir; the compiler is a sibling crate.
        for (p in listOf("release", "debug")) {
            val f = File("../igniter-compiler/target/$p/igniter_compiler")
            if (f.canExecute()) return f.absoluteFile
        }
        return null
    }

    private fun fixtureSource(): File =
        File(javaClass.classLoader.getResource("fixtures/add.ig")!!.toURI())

    private fun compile(binary: File, source: File, outIgapp: File): Int {
        val p = ProcessBuilder(binary.absolutePath, "compile", source.absolutePath, "--out", outIgapp.absolutePath)
            .redirectErrorStream(true).start()
        p.inputStream.readBytes()   // drain
        return p.waitFor()
    }

    @Test fun `live compile produces artifacts and a non-empty semantic model (success layout)`() {
        val binary = resolveBinary()
        assumeTrue("igniter_compiler not built — skipping live proof", binary != null)

        val tmp = Files.createTempDirectory("igniter_live").toFile()
        val igapp = File(tmp, "add.igapp")
        val exit = compile(binary!!, fixtureSource(), igapp)
        assertEquals(0, exit)

        // Success layout: report + sourcemap + SIR inside the bundle.
        assertTrue(File(igapp, "compilation_report.json").exists())
        assertTrue(File(igapp, "sourcemap.json").exists())
        assertTrue(File(igapp, "semantic_ir_program.json").exists())

        val model = IgniterModelParser.parse(igapp)
        assertTrue(!model.isEmpty)
        val sum = model.byNodeId("compute:Add.sum")!!
        assertEquals(listOf("a", "b"), sum.deps)
        assertEquals("Integer", sum.type?.render())
    }

    @Test fun `live refusal writes a sibling report with parseable diagnostics`() {
        val binary = resolveBinary()
        assumeTrue("igniter_compiler not built — skipping live proof", binary != null)

        val tmp = Files.createTempDirectory("igniter_live_bad").toFile()
        val bad = File(tmp, "bad.ig")
        bad.writeText("contract Bad {\n  output r: Integer = is_some(x)\n}\n")
        val exit = compile(binary!!, bad, File(tmp, "bad.igapp"))
        assertTrue("refusal should be non-zero", exit != 0)

        // Refusal layout: sibling report next to the bundle.
        val sibling = File(tmp, "bad.compilation_report.json")
        assertTrue(sibling.exists())

        val diags = IgniterReportParser.parseReport(sibling.readText())
        assertTrue(diags.isNotEmpty())
        assertTrue(diags.first().code.startsWith("OOF-"))
    }
}
