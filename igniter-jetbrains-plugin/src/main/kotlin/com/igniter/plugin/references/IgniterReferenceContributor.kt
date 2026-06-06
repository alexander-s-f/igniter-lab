package com.igniter.plugin.references

import com.igniter.plugin.lang.IgniterTokenTypes
import com.intellij.openapi.util.TextRange
import com.intellij.patterns.PlatformPatterns
import com.intellij.psi.*
import com.intellij.util.ProcessingContext

class IgniterReferenceContributor : PsiReferenceContributor() {
    override fun registerReferenceProviders(registrar: PsiReferenceRegistrar) {
        registrar.registerReferenceProvider(
            PlatformPatterns.psiElement(IgniterTokenTypes.IDENTIFIER),
            object : PsiReferenceProvider() {
                override fun getReferencesByElement(
                    element: PsiElement,
                    context: ProcessingContext
                ): Array<PsiReference> {
                    val name = element.text.trim()
                    if (name.isBlank() || name.length < 2) return PsiReference.EMPTY_ARRAY
                    // Skip if it's a declaration keyword context (preceded by contract/def/input/output/compute)
                    val prevSibling = element.prevSibling?.text?.trim()
                    if (prevSibling in setOf("contract", "def", "module", "type", "trait")) {
                        return PsiReference.EMPTY_ARRAY
                    }
                    return arrayOf(
                        IgniterSymbolReference(element, TextRange(0, element.textLength), name)
                    )
                }
            }
        )
    }
}
