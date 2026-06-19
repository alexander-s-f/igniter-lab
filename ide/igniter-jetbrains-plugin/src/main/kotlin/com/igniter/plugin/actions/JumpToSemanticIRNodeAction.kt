package com.igniter.plugin.actions

import com.igniter.plugin.lang.IgniterFile
import com.igniter.plugin.model.IgniterModelService
import com.igniter.plugin.model.SymbolNode
import com.intellij.notification.NotificationGroupManager
import com.intellij.notification.NotificationType
import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.actionSystem.CommonDataKeys
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.fileEditor.OpenFileDescriptor
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task
import com.intellij.openapi.project.Project
import com.intellij.openapi.vfs.LocalFileSystem

/**
 * Jumps from the declaration under the caret to its node in
 * `semantic_ir_program.json` (the canonical compiler artifact), located by
 * `node_id`. The inverse of reading the source — a navigation unique to a
 * contract-native language where the SIR is the real program.
 */
class JumpToSemanticIRNodeAction : AnAction() {

    override fun update(e: AnActionEvent) {
        e.presentation.isEnabledAndVisible = e.getData(CommonDataKeys.PSI_FILE) is IgniterFile
    }

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val psiFile = e.getData(CommonDataKeys.PSI_FILE) as? IgniterFile ?: return
        val editor  = e.getData(CommonDataKeys.EDITOR) ?: return
        val vFile   = psiFile.virtualFile ?: return

        val text   = psiFile.text
        val path   = vFile.path
        val name   = vFile.name
        val offset = editor.caretModel.offset
        val caretLine = editor.document.getLineNumber(offset) + 1
        val nameAtCaret = psiFile.findElementAt(offset)?.text?.trim()

        ProgressManager.getInstance().run(object : Task.Backgroundable(project, "Resolving Semantic IR node…", true) {
            override fun run(indicator: ProgressIndicator) {
                indicator.isIndeterminate = true
                val analysis = IgniterModelService.getInstance(project).analyze(name, path, text)
                val model = analysis.model

                val target = pickTarget(model.symbols, caretLine, nameAtCaret)
                    ?: model.resolveRef(nameAtCaret ?: "", model.enclosingContract(caretLine)?.contract)
                val sirFile = model.semanticIrFile

                ApplicationManager.getApplication().invokeLater {
                    if (target == null || sirFile == null || !sirFile.exists()) {
                        notify(project, "No Semantic IR node found at caret. Does the file compile?", NotificationType.WARNING)
                        return@invokeLater
                    }
                    val sirText = runCatching { sirFile.readText() }.getOrNull() ?: ""
                    val nodeOffset = sirText.indexOf("\"${target.nodeId}\"").coerceAtLeast(0)

                    val vSir = LocalFileSystem.getInstance().refreshAndFindFileByIoFile(sirFile)
                    if (vSir == null) {
                        notify(project, "Could not open ${sirFile.path}", NotificationType.ERROR)
                        return@invokeLater
                    }
                    OpenFileDescriptor(project, vSir, nodeOffset).navigate(true)
                }
            }
        })
    }

    /** The declaration on the caret line (preferring a name match), else null. */
    private fun pickTarget(symbols: List<SymbolNode>, caretLine: Int, name: String?): SymbolNode? {
        val onLine = symbols.filter { it.line == caretLine }
        return onLine.firstOrNull { it.name == name } ?: onLine.firstOrNull()
    }

    private fun notify(project: Project, message: String, type: NotificationType) {
        NotificationGroupManager.getInstance()
            .getNotificationGroup("Igniter Compiler")
            .createNotification("Igniter", message, type)
            .notify(project)
    }
}
