package com.igniter.plugin.lang

import com.intellij.lang.Language

object IgniterLanguage : Language("Igniter") {
    private fun readResolve(): Any = IgniterLanguage

    override fun getDisplayName(): String = "Igniter Contract"
    override fun isCaseSensitive(): Boolean = true
}
