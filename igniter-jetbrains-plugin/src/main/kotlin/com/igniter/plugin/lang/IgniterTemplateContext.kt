package com.igniter.plugin.lang

import com.intellij.codeInsight.template.TemplateActionContext
import com.intellij.codeInsight.template.TemplateContextType

class IgniterTemplateContext : TemplateContextType("IGNITER") {
    override fun isInContext(templateActionContext: TemplateActionContext): Boolean =
        templateActionContext.file is IgniterFile

    override fun getPresentableName(): String = "Igniter"
}
