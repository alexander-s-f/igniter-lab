package com.igniter.plugin.quickfix

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Proves the pure quickfix policy (Card LAB-JETBRAINS-DIAGNOSTIC-QUICKFIX-P3,
 * acceptance 1, 2). No IntelliJ fixture needed.
 */
class IgniterQuickFixPlannerTest {

    @Test fun `PLUGIN-001 gets the configure-compiler-path fix`() {
        assertEquals(IgniterQuickFix.CONFIGURE_COMPILER_PATH, IgniterQuickFixPlanner.planFor("PLUGIN-001"))
    }

    @Test fun `compiler OOF and other diagnostics get no fix`() {
        for (code in listOf("OOF-P0", "OOF-TY0", "OOF-L3", "PLUGIN-002", "UNKNOWN", "")) {
            assertNull("expected no quickfix for $code", IgniterQuickFixPlanner.planFor(code))
        }
    }

    @Test fun `configure-compiler-path display text is stable`() {
        assertEquals("Configure igniter_compiler path…", IgniterQuickFix.CONFIGURE_COMPILER_PATH.displayText)
        // Adapter exposes the same text and a stable family name.
        val fix = ConfigureCompilerPathQuickFix()
        assertEquals("Configure igniter_compiler path…", fix.text)
        assertEquals("Igniter", fix.familyName)
        assertEquals(false, fix.startInWriteAction())
    }
}
