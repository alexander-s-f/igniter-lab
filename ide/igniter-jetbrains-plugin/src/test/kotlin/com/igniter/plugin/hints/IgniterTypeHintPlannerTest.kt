package com.igniter.plugin.hints

import com.igniter.plugin.model.IgniterModel
import com.igniter.plugin.model.IgniterModelParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * Proves the pure type-hint policy (Card LAB-JETBRAINS-INLAY-TYPE-HINTS-P2,
 * acceptance 1–4) against the REAL `fixtures/add.igapp` artifacts.
 */
class IgniterTypeHintPlannerTest {

    private fun model(): IgniterModel =
        IgniterModelParser.parse(File(javaClass.classLoader.getResource("fixtures/add.igapp")!!.toURI()))

    @Test fun `emits Integer hint for the compute node`() {
        val hints = IgniterTypeHintPlanner.plan(model())
        val sum = hints.single { it.nodeId == "compute:Add.sum" }
        assertEquals(": Integer", sum.text)
        assertEquals(7, sum.line)   // fixtures/add.ig: `  compute sum = a + b`
    }

    @Test fun `does not hint explicit input or output declarations`() {
        val ids = IgniterTypeHintPlanner.plan(model()).map { it.nodeId }.toSet()
        assertTrue("inputs/outputs must not be hinted (v0 policy)",
            ids.none { it.startsWith("input:") || it.startsWith("output:") || it.startsWith("contract:") })
    }

    @Test fun `v0 policy hints only compute nodes`() {
        val hints = IgniterTypeHintPlanner.plan(model())
        assertEquals(listOf("compute:Add.sum"), hints.map { it.nodeId })
    }

    @Test fun `empty model yields no hints`() {
        val empty = IgniterModelParser.parse(Files.createTempDirectory("igniter_hints_empty").toFile())
        assertTrue(IgniterTypeHintPlanner.plan(empty).isEmpty())
        assertTrue(IgniterTypeHintPlanner.plan(IgniterModel.EMPTY).isEmpty())
    }

    @Test fun `plan is deterministic and stable for the fixture`() {
        assertEquals(IgniterTypeHintPlanner.plan(model()), IgniterTypeHintPlanner.plan(model()))
    }

    @Test fun `no hint when type is null`() {
        // A synthetic model with a typeless compute must produce nothing.
        val m = IgniterModel(
            module = "M",
            symbols = listOf(
                com.igniter.plugin.model.SymbolNode(
                    nodeId = "compute:M.x", kind = "compute", name = "x", contract = "M",
                    type = null, line = 3, col = 1, sirPath = null, deps = emptyList()
                )
            ),
            igappDir = null, semanticIrFile = null, sourceMapFile = null
        )
        assertTrue(IgniterTypeHintPlanner.plan(m).isEmpty())
    }
}
