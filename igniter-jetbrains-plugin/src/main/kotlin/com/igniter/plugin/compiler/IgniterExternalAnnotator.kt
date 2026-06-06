package com.igniter.plugin.compiler

import com.igniter.plugin.lang.IgniterFile
import com.igniter.plugin.settings.IgniterSettings
import com.intellij.lang.annotation.AnnotationHolder
import com.intellij.lang.annotation.ExternalAnnotator
import com.intellij.lang.annotation.HighlightSeverity
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.util.TextRange
import com.intellij.psi.PsiFile
import java.io.File

/**
 * Runs the Igniter compiler on each .ig file and maps OOF diagnostics back to
 * editor annotations.  The annotator is triggered after every PSI change (i.e.
 * on every keystroke once highlighting is stable) but we guard with the
 * "auto-compile on save" preference so power users can opt out of continuous
 * recompilation.
 */
class IgniterExternalAnnotator : ExternalAnnotator<PsiFile, List<OofDiagnostic>>() {

    private val log = Logger.getInstance(IgniterExternalAnnotator::class.java)

    // Phase 1 — collect file info on the EDT
    override fun collectInformation(file: PsiFile): PsiFile? {
        if (file !is IgniterFile) return null
        val settings = IgniterSettings.getInstance()
        if (!settings.autoCompileOnSave) return null
        return file
    }

    // Phase 2 — run compiler on a background thread
    override fun doAnnotate(collectedInfo: PsiFile?): List<OofDiagnostic>? {
        collectedInfo ?: return null
        val vFile = collectedInfo.virtualFile ?: return null
        val ioFile = File(vFile.path)
        if (!ioFile.exists()) return null

        return try {
            val result = IgniterCompilerService.getInstance().compile(ioFile)
            result.diagnostics
        } catch (e: Exception) {
            log.warn("ExternalAnnotator compile failed", e)
            null
        }
    }

    // Phase 3 — apply annotations on the EDT
    override fun apply(file: PsiFile, diagnostics: List<OofDiagnostic>?, holder: AnnotationHolder) {
        diagnostics ?: return
        val document = com.intellij.openapi.fileEditor.FileDocumentManager.getInstance()
            .getDocument(file.virtualFile ?: return) ?: return

        for (diag in diagnostics) {
            val lineIndex = (diag.line - 1).coerceAtLeast(0)
            if (lineIndex >= document.lineCount) continue

            val lineStart = document.getLineStartOffset(lineIndex)
            val lineEnd   = document.getLineEndOffset(lineIndex)
            val colOffset = (diag.col - 1).coerceAtLeast(0)
            val start     = (lineStart + colOffset).coerceAtMost(lineEnd)
            // Highlight at least one character so the annotation is visible
            val end       = if (start < lineEnd) start + 1 else lineEnd

            val range = TextRange(start, end)
            val tooltip = "[${diag.code}] ${diag.message}"

            when (diag.severity) {
                OofSeverity.ERROR -> holder.newAnnotation(HighlightSeverity.ERROR, tooltip)
                    .range(range)
                    .tooltip(tooltip)
                    .create()

                OofSeverity.WARNING -> holder.newAnnotation(HighlightSeverity.WARNING, tooltip)
                    .range(range)
                    .tooltip(tooltip)
                    .create()

                OofSeverity.INFO -> holder.newAnnotation(HighlightSeverity.INFORMATION, tooltip)
                    .range(range)
                    .tooltip(tooltip)
                    .create()
            }
        }
    }
}
