package com.igniter.plugin.lang

import com.intellij.openapi.editor.colors.TextAttributesKey
import com.intellij.openapi.fileTypes.SyntaxHighlighter
import com.intellij.openapi.options.colors.AttributesDescriptor
import com.intellij.openapi.options.colors.ColorDescriptor
import com.intellij.openapi.options.colors.ColorSettingsPage
import javax.swing.Icon

class IgniterColorSettingsPage : ColorSettingsPage {

    private companion object {
        val DESCRIPTORS = arrayOf(
            AttributesDescriptor("Keyword",                     IgniterHighlighterColors.KEYWORD),
            AttributesDescriptor("Type name",                   IgniterHighlighterColors.TYPE_NAME),
            AttributesDescriptor("Literals//String",            IgniterHighlighterColors.STRING_LITERAL),
            AttributesDescriptor("Literals//Integer",           IgniterHighlighterColors.INTEGER_LITERAL),
            AttributesDescriptor("Literals//Float",             IgniterHighlighterColors.FLOAT_LITERAL),
            AttributesDescriptor("Literals//Boolean",           IgniterHighlighterColors.BOOL_LITERAL),
            AttributesDescriptor("Literals//Symbol (:atom)",    IgniterHighlighterColors.SYMBOL_LITERAL),
            AttributesDescriptor("Comment",                     IgniterHighlighterColors.COMMENT),
            AttributesDescriptor("Delimiters//Operator",        IgniterHighlighterColors.OPERATOR),
            AttributesDescriptor("Delimiters//Arrow (->)",      IgniterHighlighterColors.ARROW),
            AttributesDescriptor("Delimiters//Braces",          IgniterHighlighterColors.BRACES),
            AttributesDescriptor("Delimiters//Brackets",        IgniterHighlighterColors.BRACKETS),
            AttributesDescriptor("Delimiters//Parentheses",     IgniterHighlighterColors.PARENS),
            AttributesDescriptor("Delimiters//Comma",           IgniterHighlighterColors.COMMA),
            AttributesDescriptor("Delimiters//Dot",             IgniterHighlighterColors.DOT),
            AttributesDescriptor("Delimiters//Colon",           IgniterHighlighterColors.COLON),
            AttributesDescriptor("Identifier",                  IgniterHighlighterColors.IDENTIFIER),
            AttributesDescriptor("Bad character",               IgniterHighlighterColors.BAD_CHARACTER),
        )

        // Demo text that exercises every token type
        val DEMO = """
-- Igniter contract demo
module Lang.Examples.Demo

import Lang.Shared.Types

def factorial(n: Integer, acc: Integer) -> Integer decreases fuel {
  if n == 0 { acc } else { factorial(n - 1, acc * n) }
}

type Priority = :high | :medium | :low

contract OrderProcessor {
  input order_id: Integer
  input priority: String
  compute is_valid = true
  compute ratio = 1.5
  compute label = "processing"
  compute tag = :active
  output result: Bool
}
""".trimIndent()
    }

    override fun getAttributeDescriptors(): Array<AttributesDescriptor> = DESCRIPTORS
    override fun getColorDescriptors(): Array<ColorDescriptor> = ColorDescriptor.EMPTY_ARRAY
    override fun getDisplayName(): String = "Igniter"
    override fun getHighlighter(): SyntaxHighlighter = IgniterSyntaxHighlighter()
    override fun getDemoText(): String = DEMO
    override fun getIcon(): Icon? = IgniterFileType.ICON
    override fun getAdditionalHighlightingTagToDescriptorMap(): Map<String, TextAttributesKey>? = null
}
