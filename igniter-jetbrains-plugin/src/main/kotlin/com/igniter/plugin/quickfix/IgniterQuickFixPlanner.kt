package com.igniter.plugin.quickfix

/** A plugin-owned, source-safe quickfix kind and its display text. */
enum class IgniterQuickFix(val displayText: String) {
    CONFIGURE_COMPILER_PATH("Configure igniter_compiler path…")
}

/**
 * Pure (IntelliJ-free) policy mapping a diagnostic code to a safe quickfix.
 * Card LAB-JETBRAINS-DIAGNOSTIC-QUICKFIX-P3.
 *
 * Only **plugin-owned, reversible** fixes are offered. Compiler OOF diagnostics
 * (`OOF-*`) need semantic judgement and get no quickfix in P3 — they must not
 * become editor folklore.
 */
internal object IgniterQuickFixPlanner {

    fun planFor(code: String): IgniterQuickFix? = when (code) {
        "PLUGIN-001" -> IgniterQuickFix.CONFIGURE_COMPILER_PATH   // igniter_compiler not found
        else -> null
    }
}
