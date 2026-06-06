package com.igniter.plugin.lang

import com.intellij.lexer.Lexer
import com.intellij.openapi.editor.DefaultLanguageHighlighterColors
import com.intellij.openapi.editor.HighlighterColors
import com.intellij.openapi.editor.colors.TextAttributesKey
import com.intellij.openapi.editor.colors.TextAttributesKey.createTextAttributesKey
import com.intellij.openapi.fileTypes.SyntaxHighlighterBase
import com.intellij.psi.tree.IElementType

object IgniterHighlighterColors {
    @JvmField val KEYWORD = createTextAttributesKey(
        "IGNITER_KEYWORD", DefaultLanguageHighlighterColors.KEYWORD
    )
    @JvmField val TYPE_NAME = createTextAttributesKey(
        "IGNITER_TYPE_NAME", DefaultLanguageHighlighterColors.CLASS_NAME
    )
    @JvmField val STRING_LITERAL = createTextAttributesKey(
        "IGNITER_STRING_LITERAL", DefaultLanguageHighlighterColors.STRING
    )
    @JvmField val INTEGER_LITERAL = createTextAttributesKey(
        "IGNITER_INTEGER_LITERAL", DefaultLanguageHighlighterColors.NUMBER
    )
    @JvmField val FLOAT_LITERAL = createTextAttributesKey(
        "IGNITER_FLOAT_LITERAL", DefaultLanguageHighlighterColors.NUMBER
    )
    @JvmField val COMMENT = createTextAttributesKey(
        "IGNITER_COMMENT", DefaultLanguageHighlighterColors.LINE_COMMENT
    )
    @JvmField val OPERATOR = createTextAttributesKey(
        "IGNITER_OPERATOR", DefaultLanguageHighlighterColors.OPERATION_SIGN
    )
    @JvmField val SYMBOL_LITERAL = createTextAttributesKey(
        "IGNITER_SYMBOL_LITERAL", DefaultLanguageHighlighterColors.CONSTANT
    )
    @JvmField val BOOL_LITERAL = createTextAttributesKey(
        "IGNITER_BOOL_LITERAL", DefaultLanguageHighlighterColors.KEYWORD
    )
    @JvmField val IDENTIFIER = createTextAttributesKey(
        "IGNITER_IDENTIFIER", DefaultLanguageHighlighterColors.IDENTIFIER
    )
    @JvmField val BAD_CHARACTER = createTextAttributesKey(
        "IGNITER_BAD_CHARACTER", HighlighterColors.BAD_CHARACTER
    )
    @JvmField val PUNCTUATION = createTextAttributesKey(
        "IGNITER_PUNCTUATION", DefaultLanguageHighlighterColors.DOT
    )
    @JvmField val BRACES = createTextAttributesKey(
        "IGNITER_BRACES", DefaultLanguageHighlighterColors.BRACES
    )
    @JvmField val BRACKETS = createTextAttributesKey(
        "IGNITER_BRACKETS", DefaultLanguageHighlighterColors.BRACKETS
    )
    @JvmField val PARENS = createTextAttributesKey(
        "IGNITER_PARENS", DefaultLanguageHighlighterColors.PARENTHESES
    )
    @JvmField val ARROW = createTextAttributesKey(
        "IGNITER_ARROW", DefaultLanguageHighlighterColors.OPERATION_SIGN
    )
    @JvmField val COMMA = createTextAttributesKey(
        "IGNITER_COMMA", DefaultLanguageHighlighterColors.COMMA
    )
    @JvmField val DOT = createTextAttributesKey(
        "IGNITER_DOT", DefaultLanguageHighlighterColors.DOT
    )
    @JvmField val COLON = createTextAttributesKey(
        "IGNITER_COLON", DefaultLanguageHighlighterColors.DOT
    )
}

class IgniterSyntaxHighlighter : SyntaxHighlighterBase() {
    override fun getHighlightingLexer(): Lexer = IgniterLexer()

    override fun getTokenHighlights(tokenType: IElementType): Array<TextAttributesKey> =
        when (tokenType) {
            IgniterTokenTypes.KEYWORD         -> pack(IgniterHighlighterColors.KEYWORD)
            IgniterTokenTypes.TYPE_NAME       -> pack(IgniterHighlighterColors.TYPE_NAME)
            IgniterTokenTypes.STRING_LITERAL  -> pack(IgniterHighlighterColors.STRING_LITERAL)
            IgniterTokenTypes.INTEGER_LITERAL -> pack(IgniterHighlighterColors.INTEGER_LITERAL)
            IgniterTokenTypes.FLOAT_LITERAL   -> pack(IgniterHighlighterColors.FLOAT_LITERAL)
            IgniterTokenTypes.COMMENT         -> pack(IgniterHighlighterColors.COMMENT)
            IgniterTokenTypes.OPERATOR        -> pack(IgniterHighlighterColors.OPERATOR)
            IgniterTokenTypes.SYMBOL_LITERAL  -> pack(IgniterHighlighterColors.SYMBOL_LITERAL)
            IgniterTokenTypes.BOOL_LITERAL    -> pack(IgniterHighlighterColors.BOOL_LITERAL)
            IgniterTokenTypes.IDENTIFIER      -> pack(IgniterHighlighterColors.IDENTIFIER)
            IgniterTokenTypes.BAD_CHARACTER   -> pack(IgniterHighlighterColors.BAD_CHARACTER)
            IgniterTokenTypes.LBRACE,
            IgniterTokenTypes.RBRACE          -> pack(IgniterHighlighterColors.BRACES)
            IgniterTokenTypes.LBRACKET,
            IgniterTokenTypes.RBRACKET        -> pack(IgniterHighlighterColors.BRACKETS)
            IgniterTokenTypes.LPAREN,
            IgniterTokenTypes.RPAREN          -> pack(IgniterHighlighterColors.PARENS)
            IgniterTokenTypes.ARROW           -> pack(IgniterHighlighterColors.ARROW)
            IgniterTokenTypes.COMMA           -> pack(IgniterHighlighterColors.COMMA)
            IgniterTokenTypes.DOT             -> pack(IgniterHighlighterColors.DOT)
            IgniterTokenTypes.COLON           -> pack(IgniterHighlighterColors.COLON)
            IgniterTokenTypes.PUNCTUATION     -> pack(IgniterHighlighterColors.PUNCTUATION)
            else                              -> emptyArray()
        }
}
