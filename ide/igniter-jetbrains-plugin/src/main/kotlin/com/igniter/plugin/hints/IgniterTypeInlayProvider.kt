package com.igniter.plugin.hints

import com.igniter.plugin.lang.IgniterFile
import com.igniter.plugin.model.IgniterModelService
import com.intellij.codeInsight.hints.declarative.InlayHintsCollector
import com.intellij.codeInsight.hints.declarative.InlayHintsProvider
import com.intellij.codeInsight.hints.declarative.InlayTreeSink
import com.intellij.codeInsight.hints.declarative.InlineInlayPosition
import com.intellij.codeInsight.hints.declarative.OwnBypassCollector
import com.intellij.openapi.editor.Editor
import com.intellij.openapi.project.Project
import com.intellij.psi.PsiDocumentManager
import com.intellij.psi.PsiFile

/**
 * Declarative inlay type hints for `.ig` files (IntelliJ EP
 * `codeInsight.declarativeInlayProvider`). Compiler-backed: types come from the
 * cached [IgniterModelService] analysis via the pure [IgniterTypeHintPlanner].
 *
 * Render path never spawns the compiler: it reads only `cached(...)`. A cold or
 * stale cache yields no hints (the annotator warms it on the same file). Empty
 * model, missing document, or unknown line all fail closed.
 */
class IgniterTypeInlayProvider : InlayHintsProvider {

    override fun createCollector(file: PsiFile, editor: Editor): InlayHintsCollector? =
        if (file is IgniterFile) Collector(file.project) else null

    private class Collector(private val project: Project) : OwnBypassCollector {

        override fun collectHintsForFile(file: PsiFile, sink: InlayTreeSink) {
            val vFile = file.virtualFile ?: return
            // Cache-only: do NOT compile on the EDT/render path.
            val analysis = IgniterModelService.getInstance(project).cached(vFile.path, file.text) ?: return
            val model = analysis.model
            if (model.isEmpty) return

            val document = PsiDocumentManager.getInstance(project).getDocument(file) ?: return

            for (hint in IgniterTypeHintPlanner.plan(model)) {
                val offset = endOfLineOffset(document, hint.line) ?: continue
                sink.addPresentation(
                    InlineInlayPosition(offset, /* relatedToPrevious = */ true, /* priority = */ 0),
                    emptyList(),
                    null,
                    hasBackground = true
                ) {
                    text(hint.text, null)
                }
            }
        }

        /** End-of-line offset for a 1-based [line], or null if out of range. */
        private fun endOfLineOffset(document: com.intellij.openapi.editor.Document, line: Int): Int? {
            val idx = line - 1
            if (idx < 0 || idx >= document.lineCount) return null
            return document.getLineEndOffset(idx)
        }
    }
}
