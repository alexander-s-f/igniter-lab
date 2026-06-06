package com.igniter.plugin.lang

import com.intellij.extapi.psi.PsiFileBase
import com.intellij.lang.ASTNode
import com.intellij.lang.ParserDefinition
import com.intellij.lang.PsiParser
import com.intellij.lexer.Lexer
import com.intellij.openapi.fileTypes.FileType
import com.intellij.openapi.project.Project
import com.intellij.psi.FileViewProvider
import com.intellij.psi.PsiElement
import com.intellij.psi.PsiFile
import com.intellij.psi.tree.IFileElementType
import com.intellij.psi.tree.TokenSet

/**
 * Minimal PSI file node — Igniter does not (yet) have a full grammar-generated parser,
 * so we use a stub that stores the entire file as a single flat token stream.
 */
class IgniterFile(viewProvider: FileViewProvider) : PsiFileBase(viewProvider, IgniterLanguage) {
    override fun getFileType(): FileType = IgniterFileType
    override fun toString(): String = "Igniter Contract File"
}

class IgniterParserDefinition : ParserDefinition {

    companion object {
        @JvmField
        val FILE = IFileElementType(IgniterLanguage)
    }

    override fun createLexer(project: Project): Lexer = IgniterLexer()

    /**
     * Igniter does not yet have a grammar-based parser.  We provide a trivial
     * parser that wraps the entire token stream in the file element so that
     * syntax highlighting and structure view still work via the lexer alone.
     */
    override fun createParser(project: Project): PsiParser = PsiParser { root, builder ->
        val marker = builder.mark()
        while (!builder.eof()) builder.advanceLexer()
        marker.done(root)
        builder.treeBuilt
    }

    override fun getFileNodeType(): IFileElementType = FILE

    override fun getCommentTokens(): TokenSet = IgniterTokenTypes.COMMENT_SET
    override fun getStringLiteralElements(): TokenSet = IgniterTokenTypes.STRING_SET
    override fun getWhitespaceTokens(): TokenSet = IgniterTokenTypes.WHITESPACE_SET

    override fun createElement(node: ASTNode): PsiElement =
        throw UnsupportedOperationException("IgniterParserDefinition.createElement should not be called")

    override fun createFile(viewProvider: FileViewProvider): PsiFile = IgniterFile(viewProvider)
}
