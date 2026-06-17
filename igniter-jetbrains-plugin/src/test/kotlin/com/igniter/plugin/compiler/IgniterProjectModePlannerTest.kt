package com.igniter.plugin.compiler

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure tests for the project-mode compile planner
 * (card LAB-JETBRAINS-PROJECT-MODE-DELEGATION-P7). No IntelliJ runtime; text
 * parsing, the project-mode decision, and the exact CLI argv are exercised directly.
 */
class IgniterProjectModePlannerTest {

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
        assertEquals("CallRouterWebhook", IgniterProjectModePlanner.moduleNameOf(webhook))
        assertNull(IgniterProjectModePlanner.moduleNameOf("pure contract X { }"))
    }

    @Test fun `importedModules ignores stdlib and dedups, preserving order`() {
        assertEquals(listOf("CallRouterTypes"), IgniterProjectModePlanner.importedModules(webhook))
    }

    @Test fun `selective import resolves to the module path before the brace`() {
        val text = "module M\nimport Lab.Order.Mapper.{ BuildHttpResult }\nimport Lab.Order.Types\n"
        assertEquals(listOf("Lab.Order.Mapper", "Lab.Order.Types"), IgniterProjectModePlanner.importedModules(text))
    }

    @Test fun `isStdlib matches the stdlib namespace only`() {
        assertTrue(IgniterProjectModePlanner.isStdlib("stdlib"))
        assertTrue(IgniterProjectModePlanner.isStdlib("stdlib.collection"))
        assertFalse(IgniterProjectModePlanner.isStdlib("stdlibrary"))
        assertFalse(IgniterProjectModePlanner.isStdlib("CallRouterTypes"))
    }

    @Test fun `project mode applies when a module has a non-stdlib import`() {
        assertEquals("CallRouterWebhook", IgniterProjectModePlanner.entryModuleForProjectMode(webhook))
    }

    @Test fun `project mode does NOT apply with no non-stdlib import`() {
        // Only a stdlib import → single-file path stays.
        val onlyStdlib = "module M\nimport stdlib.collection.{ count }\npure contract C { output n : Integer }\n"
        assertNull(IgniterProjectModePlanner.entryModuleForProjectMode(onlyStdlib))
        // No imports at all.
        assertNull(IgniterProjectModePlanner.entryModuleForProjectMode("module M\npure contract C { }"))
        // No module declaration → cannot be an entry.
        assertNull(IgniterProjectModePlanner.entryModuleForProjectMode("import Other\npure contract C { }"))
    }

    @Test fun `buildCompileArgs emits the exact project-mode plus overlay CLI shape`() {
        val args = IgniterProjectModePlanner.buildCompileArgs(
            binary = "/bin/igniter_compiler",
            projectRoot = "/proj",
            entryModule = "CallRouterWebhook",
            overlayOriginal = "/proj/webhook.ig",
            overlayBuffer = "/tmp/buf/webhook.ig",
            outIgapp = "/tmp/out/webhook.igapp",
        )
        assertEquals(
            listOf(
                "/bin/igniter_compiler", "compile",
                "--project-root", "/proj",
                "--entry", "CallRouterWebhook",
                "--overlay", "/proj/webhook.ig=/tmp/buf/webhook.ig",
                "--out", "/tmp/out/webhook.igapp",
            ),
            args
        )
    }
}
