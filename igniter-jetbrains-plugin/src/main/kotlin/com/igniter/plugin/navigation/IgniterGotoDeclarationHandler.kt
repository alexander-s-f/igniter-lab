package com.igniter.plugin.navigation

import com.igniter.plugin.lang.IgniterFile
import com.igniter.plugin.lang.IgniterTokenTypes
import com.igniter.plugin.model.IgniterModelService
import com.intellij.codeInsight.navigation.actions.GotoDeclarationHandler
import com.intellij.openapi.editor.Editor
import com.intellij.psi.PsiDocumentManager
import com.intellij.psi.PsiElement

/**
 * Ctrl+Click / Go-to-Declaration for Igniter identifiers, resolved through the
 * compiler-backed [IgniterModelService] (semantic, not regex).
 *
 * Uses only the cached analysis — never spawns the compiler on the EDT. The
 * annotator keeps the cache warm for the focused file, so navigation is live in
 * practice; on a cold cache it simply yields no target until the next analysis.
 */
class IgniterGotoDeclarationHandler : GotoDeclarationHandler {

    override fun getGotoDeclarationTargets(
        sourceElement: PsiElement?,
        offset: Int,
        editor: Editor?
    ): Array<PsiElement>? {
        val element = sourceElement ?: return null
        if (element.node?.elementType != IgniterTokenTypes.IDENTIFIER) return null

        val file = element.containingFile as? IgniterFile ?: return null
        val vFile = file.virtualFile ?: return null
        val project = file.project

        val analysis = IgniterModelService.getInstance(project).cached(vFile.path, file.text) ?: return null
        val model = analysis.model
        if (model.isEmpty) return null

        val document = editor?.document
            ?: PsiDocumentManager.getInstance(project).getDocument(file)
            ?: return null

        val name = element.text
        val caretLine = document.getLineNumber(offset) + 1
        val contract = model.enclosingContract(caretLine)?.contract

        val target = model.resolveRef(name, contract) ?: return null
        if (target.line <= 0) return null

        val targetOffset = offsetOf(document, target.line, target.col)
        // Don't navigate to the identifier the caret is already on (it's the decl itself).
        if (targetOffset == element.textRange.startOffset) return null

        val targetElement = file.findElementAt(targetOffset) ?: return null
        return arrayOf(targetElement)
    }

    private fun offsetOf(document: com.intellij.openapi.editor.Document, line: Int, col: Int): Int {
        val lineIdx = (line - 1).coerceIn(0, (document.lineCount - 1).coerceAtLeast(0))
        val start = document.getLineStartOffset(lineIdx)
        val end = document.getLineEndOffset(lineIdx)
        return (start + (col - 1).coerceAtLeast(0)).coerceIn(start, end)
    }
}
