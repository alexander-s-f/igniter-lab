package com.igniter.plugin.references

import com.igniter.plugin.index.IgniterSymbolIndex
import com.intellij.codeInsight.lookup.LookupElementBuilder
import com.intellij.openapi.util.TextRange
import com.intellij.psi.*
import com.intellij.psi.search.GlobalSearchScope
import com.intellij.util.indexing.FileBasedIndex

class IgniterSymbolReference(
    element: PsiElement,
    rangeInElement: TextRange,
    private val symbolName: String
) : PsiReferenceBase<PsiElement>(element, rangeInElement) {

    override fun resolve(): PsiElement? {
        val project = element.project
        val index = FileBasedIndex.getInstance()
        val scope = GlobalSearchScope.allScope(project)

        // Try qualified kinds first (contract > def > compute > input > output)
        val kinds = listOf("contract", "def", "compute", "input", "output", "loop")
        for (kind in kinds) {
            val key = "$kind:$symbolName"
            val files = index.getContainingFiles(IgniterSymbolIndex.NAME, key, scope)
            for (vf in files) {
                val offsets = index.getValues(
                    IgniterSymbolIndex.NAME, key,
                    GlobalSearchScope.fileScope(project, vf)
                )
                val off = offsets.firstOrNull() ?: continue
                val psiFile = PsiManager.getInstance(project).findFile(vf) ?: continue
                return psiFile.findElementAt(off)
            }
        }
        return null
    }

    override fun getVariants(): Array<Any> {
        // Provide all known symbol names as variants for completion fallback
        val project = element.project
        val index = FileBasedIndex.getInstance()
        val scope = GlobalSearchScope.allScope(project)
        val names = mutableSetOf<String>()
        index.processAllKeys(IgniterSymbolIndex.NAME, { key ->
            if (!key.contains(':')) names.add(key)
            true
        }, scope, null)
        return names.map { LookupElementBuilder.create(it) }.toTypedArray()
    }
}
