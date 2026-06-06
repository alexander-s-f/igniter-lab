package com.igniter.plugin.lang

import com.intellij.psi.tree.IElementType
import com.intellij.psi.tree.TokenSet

class IgniterElementType(debugName: String) : IElementType(debugName, IgniterLanguage)

object IgniterTokenTypes {
    @JvmField val KEYWORD         = IgniterElementType("KEYWORD")
    @JvmField val TYPE_NAME       = IgniterElementType("TYPE_NAME")
    @JvmField val IDENTIFIER      = IgniterElementType("IDENTIFIER")
    @JvmField val INTEGER_LITERAL = IgniterElementType("INTEGER_LITERAL")
    @JvmField val FLOAT_LITERAL   = IgniterElementType("FLOAT_LITERAL")
    @JvmField val STRING_LITERAL  = IgniterElementType("STRING_LITERAL")
    @JvmField val SYMBOL_LITERAL  = IgniterElementType("SYMBOL_LITERAL")
    @JvmField val BOOL_LITERAL    = IgniterElementType("BOOL_LITERAL")
    @JvmField val OPERATOR        = IgniterElementType("OPERATOR")
    @JvmField val PUNCTUATION     = IgniterElementType("PUNCTUATION")
    @JvmField val COMMENT         = IgniterElementType("COMMENT")
    @JvmField val WHITESPACE      = IgniterElementType("WHITESPACE")
    @JvmField val BAD_CHARACTER   = IgniterElementType("BAD_CHARACTER")

    // Specific punctuation tokens
    @JvmField val LBRACE    = IgniterElementType("LBRACE")
    @JvmField val RBRACE    = IgniterElementType("RBRACE")
    @JvmField val LPAREN    = IgniterElementType("LPAREN")
    @JvmField val RPAREN    = IgniterElementType("RPAREN")
    @JvmField val LBRACKET  = IgniterElementType("LBRACKET")
    @JvmField val RBRACKET  = IgniterElementType("RBRACKET")
    @JvmField val COLON     = IgniterElementType("COLON")
    @JvmField val DOT       = IgniterElementType("DOT")
    @JvmField val COMMA     = IgniterElementType("COMMA")
    @JvmField val ARROW     = IgniterElementType("ARROW")

    @JvmField val WHITESPACE_SET = TokenSet.create(WHITESPACE)
    @JvmField val COMMENT_SET    = TokenSet.create(COMMENT)
    @JvmField val STRING_SET     = TokenSet.create(STRING_LITERAL)

    val KEYWORDS: Set<String> = setOf(
        "module", "import", "contract", "def", "type", "trait", "impl",
        "input", "output", "compute", "read", "snapshot", "window",
        "escape", "stream", "fold_stream", "assumptions", "olap_point",
        "if", "else", "let", "loop", "service", "pipeline", "step",
        "pure", "observed", "effect", "privileged", "irreversible",
        "from", "lifecycle", "scoped_by", "cardinality", "max_steps",
        "decreases", "fuel", "evidence", "invariant", "predicate",
        "severity", "uses", "in", "emit"
    )

    val BOOL_LITERALS: Set<String> = setOf("true", "false")

    val BUILT_IN_TYPES: Set<String> = setOf(
        "Integer", "Float", "String", "Bool", "Decimal", "Collection",
        "Array", "Option", "History", "BiHistory", "OLAPPoint",
        "DateTime", "Nil", "ClockTick"
    )
}
