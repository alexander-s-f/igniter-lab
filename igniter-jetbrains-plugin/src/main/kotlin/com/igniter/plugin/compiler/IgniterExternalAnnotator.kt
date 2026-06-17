package com.igniter.plugin.compiler

import com.igniter.plugin.lang.IgniterFile
import com.igniter.plugin.model.IgniterModelService
import com.igniter.plugin.quickfix.ConfigureCompilerPathQuickFix
import com.igniter.plugin.quickfix.IgniterQuickFix
import com.igniter.plugin.quickfix.IgniterQuickFixPlanner
import com.igniter.plugin.settings.IgniterSettings
import com.intellij.codeInsight.intention.IntentionAction
import com.intellij.lang.annotation.AnnotationHolder
import com.intellij.lang.annotation.ExternalAnnotator
import com.intellij.lang.annotation.HighlightSeverity
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.Project
import com.intellij.openapi.util.TextRange
import com.intellij.psi.PsiFile

/**
 * Runs the Igniter compiler on each .ig file and maps OOF diagnostics back to
 * editor annotations.  The annotator is triggered after every PSI change (i.e.
 * on every keystroke once highlighting is stable) but we guard with the
 * "auto-compile on save" preference so power users can opt out of continuous
 * recompilation.
 *
 * Goes through [IgniterModelService] so it analyses the *editor text* (unsaved
 * edits included) and shares the one compile per content hash with navigation
 * and hints.
 */
class IgniterExternalAnnotator : ExternalAnnotator<IgniterExternalAnnotator.Request, List<OofDiagnostic>>() {

    private val log = Logger.getInstance(IgniterExternalAnnotator::class.java)

    data class Request(val project: Project, val name: String, val path: String, val text: String)

    // Phase 1 — collect file + current document text on the EDT
    override fun collectInformation(file: PsiFile): Request? {
        if (file !is IgniterFile) return null
        if (!IgniterSettings.getInstance().autoCompileOnSave) return null
        val vFile = file.virtualFile ?: return null
        return Request(file.project, vFile.name, vFile.path, file.text)
    }

    // Phase 2 — run compiler on a background thread (via the shared analysis cache)
    override fun doAnnotate(collectedInfo: Request?): List<OofDiagnostic>? {
        val req = collectedInfo ?: return null
        return try {
            IgniterModelService.getInstance(req.project)
                .analyze(req.name, req.path, req.text)
                .diagnostics
        } catch (e: Exception) {
            log.warn("ExternalAnnotator analysis failed", e)
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
            val severity = when (diag.severity) {
                OofSeverity.ERROR   -> HighlightSeverity.ERROR
                OofSeverity.WARNING -> HighlightSeverity.WARNING
                OofSeverity.INFO    -> HighlightSeverity.INFORMATION
            }

            var builder = holder.newAnnotation(severity, tooltip).range(range).tooltip(tooltip)
            // Attach a safe, plugin-owned quickfix when the planner approves one.
            IgniterQuickFixPlanner.planFor(diag.code)?.let { spec ->
                builder = builder.withFix(quickFixFor(spec))
            }
            builder.create()
        }
    }

    private fun quickFixFor(spec: IgniterQuickFix): IntentionAction = when (spec) {
        IgniterQuickFix.CONFIGURE_COMPILER_PATH -> ConfigureCompilerPathQuickFix()
    }
}
