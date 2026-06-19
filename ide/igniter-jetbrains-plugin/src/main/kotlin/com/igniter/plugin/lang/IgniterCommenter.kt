package com.igniter.plugin.lang

import com.intellij.lang.CodeDocumentationAwareCommenter
import com.intellij.psi.PsiComment
import com.intellij.psi.tree.IElementType

/**
 * Igniter uses `--` for single-line comments (Haskell/Elm style).
 * There is no block comment syntax.
 */
class IgniterCommenter : CodeDocumentationAwareCommenter {
    override fun getLineCommentPrefix(): String = "-- "
    override fun getBlockCommentPrefix(): String? = null
    override fun getBlockCommentSuffix(): String? = null
    override fun getCommentedBlockCommentPrefix(): String? = null
    override fun getCommentedBlockCommentSuffix(): String? = null
    override fun getLineCommentTokenType(): IElementType = IgniterTokenTypes.COMMENT
    override fun getBlockCommentTokenType(): IElementType? = null
    override fun getDocumentationCommentTokenType(): IElementType? = null
    override fun getDocumentationCommentPrefix(): String? = null
    override fun getDocumentationCommentLinePrefix(): String? = null
    override fun getDocumentationCommentSuffix(): String? = null
    override fun isDocumentationComment(element: PsiComment?): Boolean = false
}
