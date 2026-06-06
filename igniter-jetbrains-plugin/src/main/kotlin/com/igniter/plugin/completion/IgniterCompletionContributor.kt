package com.igniter.plugin.completion

import com.igniter.plugin.lang.IgniterTokenTypes
import com.intellij.codeInsight.completion.*
import com.intellij.codeInsight.lookup.LookupElementBuilder
import com.intellij.patterns.PlatformPatterns
import com.intellij.util.ProcessingContext

class IgniterCompletionContributor : CompletionContributor() {

    init {
        extend(
            CompletionType.BASIC,
            PlatformPatterns.psiElement(),
            IgniterContextAwareProvider()
        )
    }

    private class IgniterContextAwareProvider : CompletionProvider<CompletionParameters>() {

        override fun addCompletions(
            parameters: CompletionParameters,
            context: ProcessingContext,
            result: CompletionResultSet
        ) {
            val offset = parameters.offset
            val docText = parameters.editor.document.text
            val textBeforeCaret = if (offset <= docText.length) docText.substring(0, offset).trimEnd() else ""

            when {
                textBeforeCaret.endsWith("lifecycle:") || textBeforeCaret.endsWith("lifecycle: ") ->
                    addSymbolSuggestions(
                        result,
                        listOf(":local", ":session", ":window", ":durable", ":audit"),
                        priority = 95.0
                    )

                textBeforeCaret.endsWith("severity:") || textBeforeCaret.endsWith("severity: ") ->
                    addSymbolSuggestions(
                        result,
                        listOf(":error", ":warn", ":soft", ":metric"),
                        priority = 95.0
                    )

                textBeforeCaret.endsWith(" from") || textBeforeCaret.endsWith("\tfrom") ->
                    addTypeSuggestions(
                        result,
                        listOf("TBackend"),
                        " (backend)",
                        priority = 90.0
                    )

                textBeforeCaret.endsWith(":") || textBeforeCaret.endsWith(": ") ->
                    addTypeCompletions(result)

                else ->
                    addKeywordCompletions(result)
            }
        }

        private fun addKeywordCompletions(result: CompletionResultSet) {
            for (keyword in IgniterTokenTypes.KEYWORDS) {
                val element = LookupElementBuilder.create(keyword)
                    .withBoldness(true)
                    .withTypeText("keyword")
                result.addElement(
                    PrioritizedLookupElement.withPriority(element, 100.0)
                )
            }
        }

        private fun addTypeCompletions(result: CompletionResultSet) {
            // Plain built-in types
            for (typeName in IgniterTokenTypes.BUILT_IN_TYPES) {
                val element = LookupElementBuilder.create(typeName)
                    .withTypeText(" (type)")
                result.addElement(
                    PrioritizedLookupElement.withPriority(element, 90.0)
                )
            }
            // Parameterized type templates
            val parameterizedTypes = listOf(
                "Decimal[\$SCALE\$]",
                "Collection[\$T\$]",
                "Array[\$T\$]",
                "History[\$T\$]",
                "BiHistory[\$T\$]"
            )
            for (tmpl in parameterizedTypes) {
                val displayName = tmpl.substringBefore("[")
                val element = LookupElementBuilder.create(tmpl)
                    .withPresentableText("$displayName[…]")
                    .withTypeText(" (type)")
                result.addElement(
                    PrioritizedLookupElement.withPriority(element, 88.0)
                )
            }
        }

        private fun addSymbolSuggestions(
            result: CompletionResultSet,
            symbols: List<String>,
            priority: Double
        ) {
            for (sym in symbols) {
                val element = LookupElementBuilder.create(sym)
                    .withTypeText(" (symbol)")
                result.addElement(
                    PrioritizedLookupElement.withPriority(element, priority)
                )
            }
        }

        private fun addTypeSuggestions(
            result: CompletionResultSet,
            names: List<String>,
            typeAnnotation: String,
            priority: Double
        ) {
            for (name in names) {
                val element = LookupElementBuilder.create(name)
                    .withTypeText(typeAnnotation)
                result.addElement(
                    PrioritizedLookupElement.withPriority(element, priority)
                )
            }
        }
    }
}
