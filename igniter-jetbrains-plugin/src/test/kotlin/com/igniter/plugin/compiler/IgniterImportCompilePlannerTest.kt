package com.igniter.plugin.compiler

import com.igniter.plugin.compiler.IgniterImportCompilePlanner.ModuleEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

/**
 * Pure tests for the import-aware compile planner (card LAB-JETBRAINS-IMPORT-AWARE-COMPILE-P6).
 * No IntelliJ runtime; parsing + graph resolution + the filesystem scan are exercised directly.
 */
class IgniterImportCompilePlannerTest {

    private val webhook = """
        module CallRouterWebhook
        import CallRouterTypes
        import stdlib.collection.{ count }

        pure contract WebhookCount {
          input call : CallrailCall
          compute n = count(call.webhooks)
          output n : Integer
        }
    """.trimIndent()

    @Test fun `moduleNameOf reads the first module line`() {
        assertEquals("CallRouterWebhook", IgniterImportCompilePlanner.moduleNameOf(webhook))
        assertNull(IgniterImportCompilePlanner.moduleNameOf("pure contract X { }"))
    }

    @Test fun `importedModules ignores stdlib and dedups, preserving order`() {
        assertEquals(listOf("CallRouterTypes"), IgniterImportCompilePlanner.importedModules(webhook))
    }

    @Test fun `selective import resolves to the module path before the brace`() {
        val text = "module M\nimport Lab.Order.Mapper.{ BuildHttpResult }\nimport Lab.Order.Types\n"
        assertEquals(listOf("Lab.Order.Mapper", "Lab.Order.Types"), IgniterImportCompilePlanner.importedModules(text))
    }

    @Test fun `isStdlib matches the stdlib namespace only`() {
        assertTrue(IgniterImportCompilePlanner.isStdlib("stdlib"))
        assertTrue(IgniterImportCompilePlanner.isStdlib("stdlib.collection"))
        assertFalse(IgniterImportCompilePlanner.isStdlib("stdlibrary"))
        assertFalse(IgniterImportCompilePlanner.isStdlib("CallRouterTypes"))
    }

    @Test fun `resolve maps a direct import to its file`() {
        val index = mapOf("CallRouterTypes" to ModuleEntry("CallRouterTypes", "/p/types.ig", emptyList()))
        assertEquals(listOf("/p/types.ig"), IgniterImportCompilePlanner.resolve("CallRouterWebhook", listOf("CallRouterTypes"), index))
    }

    @Test fun `resolve follows transitive imports with a visited set`() {
        val index = mapOf(
            "A" to ModuleEntry("A", "/p/a.ig", listOf("B")),
            "B" to ModuleEntry("B", "/p/b.ig", listOf("C", "stdlib.x")),
            "C" to ModuleEntry("C", "/p/c.ig", listOf("A"))   // cycle back to current
        )
        assertEquals(listOf("/p/a.ig", "/p/b.ig", "/p/c.ig"),
            IgniterImportCompilePlanner.resolve("Cur", listOf("A"), index))
    }

    @Test fun `resolve excludes the current module and skips unknown modules`() {
        val index = mapOf(
            "Cur" to ModuleEntry("Cur", "/p/cur.ig", emptyList()),
            "Known" to ModuleEntry("Known", "/p/known.ig", emptyList())
        )
        // Imports Cur (self — must be excluded) and Missing (not in index — skipped).
        assertEquals(listOf("/p/known.ig"),
            IgniterImportCompilePlanner.resolve("Cur", listOf("Cur", "Known", "Missing"), index))
    }

    @Test fun `resolve output is deterministic (sorted) regardless of import order`() {
        val index = mapOf(
            "A" to ModuleEntry("A", "/p/zzz.ig", emptyList()),
            "B" to ModuleEntry("B", "/p/aaa.ig", emptyList())
        )
        assertEquals(listOf("/p/aaa.ig", "/p/zzz.ig"), IgniterImportCompilePlanner.resolve("Cur", listOf("A", "B"), index))
        assertEquals(listOf("/p/aaa.ig", "/p/zzz.ig"), IgniterImportCompilePlanner.resolve("Cur", listOf("B", "A"), index))
    }

    @Test fun `scanProject indexes module to file, excludes current, skips build dirs`() {
        val root = Files.createTempDirectory("igniter_scan")
        Files.writeString(root.resolve("types.ig"), "module CallRouterTypes\ntype T { a: String }\n")
        Files.writeString(root.resolve("webhook.ig"), webhook)
        // a build artifact that must be skipped
        val build = Files.createDirectories(root.resolve("build").resolve("nested"))
        Files.writeString(build.resolve("stale.ig"), "module CallRouterTypes\n")
        // exclude the current (webhook) file from the index
        val currentPath = root.resolve("webhook.ig").toAbsolutePath().toString()

        val index = IgniterImportCompilePlanner.scanProject(root, excludePath = currentPath)

        assertTrue("types module indexed", index.containsKey("CallRouterTypes"))
        assertEquals(root.resolve("types.ig").toAbsolutePath().toString(), index["CallRouterTypes"]!!.filePath)
        assertFalse("current file excluded from index", index.containsKey("CallRouterWebhook"))
        // the build/ copy must not have won the CallRouterTypes slot
        assertFalse(index["CallRouterTypes"]!!.filePath.contains("/build/"))
    }
}
