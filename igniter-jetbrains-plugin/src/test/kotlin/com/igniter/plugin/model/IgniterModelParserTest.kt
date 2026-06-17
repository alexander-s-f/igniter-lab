package com.igniter.plugin.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * Proves the compiler-backed semantic model (Card LAB-JETBRAINS-SEMANTIC-NAV-PROOF-P1,
 * check B + the navigation-underlying functions of check C) against REAL artifacts
 * produced by the live `igniter_compiler` and committed under test resources.
 *
 * Fixture: `fixtures/add.ig` -> `fixtures/add.igapp/{sourcemap,semantic_ir_program}.json`
 * (contract Add; inputs a,b: Integer; compute sum = a + b; output sum: Integer).
 */
class IgniterModelParserTest {

    private fun addIgapp(): File =
        File(javaClass.classLoader.getResource("fixtures/add.igapp")!!.toURI())

    private fun model(): IgniterModel = IgniterModelParser.parse(addIgapp())

    @Test fun `module name comes from artifacts`() {
        assertEquals("Lang.Examples.Add", model().module)
    }

    @Test fun `symbols cover contract inputs compute and output`() {
        val ids = model().symbols.map { it.nodeId }.toSet()
        assertTrue(ids.containsAll(setOf(
            "contract:Add", "input:Add.a", "input:Add.b", "compute:Add.sum", "output:Add.sum"
        )))
    }

    @Test fun `input symbol carries kind name contract type and source location`() {
        val a = model().byNodeId("input:Add.a")!!
        assertEquals("input", a.kind)
        assertEquals("a", a.name)
        assertEquals("Add", a.contract)
        assertEquals("Integer", a.type?.render())
        assertEquals(4, a.line)   // fixtures/add.ig: `  input  a: Integer`
        assertEquals(3, a.col)
    }

    @Test fun `compute symbol carries inferred type and dependency edges`() {
        val sum = model().byNodeId("compute:Add.sum")!!
        assertEquals("compute", sum.kind)
        assertEquals("Integer", sum.type?.render())
        assertEquals(listOf("a", "b"), sum.deps)
        assertEquals(7, sum.line)
    }

    @Test fun `resolveRef resolves a reference to its input declaration`() {
        val target = model().resolveRef("a", "Add")
        assertNotNull(target)
        assertEquals("input:Add.a", target!!.nodeId)
    }

    @Test fun `usagesOf reports the compute node that depends on the input`() {
        val users = model().usagesOf("a", "Add").map { it.nodeId }
        assertTrue("compute:Add.sum" in users)
    }

    @Test fun `enclosingContract finds Add for an inner line`() {
        assertEquals("Add", model().enclosingContract(7)?.contract)
    }

    @Test fun `empty bundle degrades to EMPTY rather than guessing`() {
        val empty = Files.createTempDirectory("igniter_model_empty").toFile()
        val m = IgniterModelParser.parse(empty)
        assertTrue(m.isEmpty)
        assertNull(m.module)
    }
}
