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
            AttributesDescriptor("Keyword",          IgniterHighlighterColors.KEYWORD),
            AttributesDescriptor("Type name",        IgniterHighlighterColors.TYPE_NAME),
            AttributesDescriptor("String literal",   IgniterHighlighterColors.STRING_LITERAL),
            AttributesDescriptor("Integer literal",  IgniterHighlighterColors.INTEGER_LITERAL),
            AttributesDescriptor("Float literal",    IgniterHighlighterColors.FLOAT_LITERAL),
            AttributesDescriptor("Bool literal",     IgniterHighlighterColors.BOOL_LITERAL),
            AttributesDescriptor("Symbol literal",   IgniterHighlighterColors.SYMBOL_LITERAL),
            AttributesDescriptor("Comment",          IgniterHighlighterColors.COMMENT),
            AttributesDescriptor("Operator",         IgniterHighlighterColors.OPERATOR),
            AttributesDescriptor("Identifier",       IgniterHighlighterColors.IDENTIFIER),
            AttributesDescriptor("Braces",           IgniterHighlighterColors.BRACES),
            AttributesDescriptor("Brackets",         IgniterHighlighterColors.BRACKETS),
            AttributesDescriptor("Parentheses",      IgniterHighlighterColors.PARENS),
            AttributesDescriptor("Arrow",            IgniterHighlighterColors.ARROW),
            AttributesDescriptor("Comma",            IgniterHighlighterColors.COMMA),
            AttributesDescriptor("Dot",              IgniterHighlighterColors.DOT),
            AttributesDescriptor("Colon",            IgniterHighlighterColors.COLON),
            AttributesDescriptor("Bad character",    IgniterHighlighterColors.BAD_CHARACTER),
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
