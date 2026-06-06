package com.igniter.plugin.lang

import com.intellij.lang.BracePair
import com.intellij.lang.PairedBraceMatcher
import com.intellij.psi.PsiFile
import com.intellij.psi.tree.IElementType

class IgniterBraceMatcher : PairedBraceMatcher {

    private val pairs = arrayOf(
        BracePair(IgniterTokenTypes.LBRACE,   IgniterTokenTypes.RBRACE,   true),
        BracePair(IgniterTokenTypes.LPAREN,   IgniterTokenTypes.RPAREN,   false),
        BracePair(IgniterTokenTypes.LBRACKET, IgniterTokenTypes.RBRACKET, false)
    )

    override fun getPairs(): Array<BracePair> = pairs
    override fun isPairedBracesAllowedBeforeType(lbraceType: IElementType, contextType: IElementType?): Boolean = true
    override fun getCodeConstructStart(file: PsiFile?, openingBraceOffset: Int): Int = openingBraceOffset
}
