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
import com.intellij.openapi.editor.Document
import com.intellij.openapi.editor.Editor
import com.intellij.openapi.fileEditor.OpenFileDescriptor
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.popup.JBPopupFactory

/**
 * Lists the nodes that depend on the declaration under the caret, from the
 * compiler's dependency graph (`deps` edges in the semantic IR). Node-level
 * "find usages": srcmap-v0 has no expression spans, so this answers "who depends
 * on this node?" rather than highlighting each reference token.
 */
class FindIgniterDependentsAction : AnAction() {

    override fun update(e: AnActionEvent) {
        e.presentation.isEnabledAndVisible = e.getData(CommonDataKeys.PSI_FILE) is IgniterFile
    }

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val psiFile = e.getData(CommonDataKeys.PSI_FILE) as? IgniterFile ?: return
        val editor  = e.getData(CommonDataKeys.EDITOR) ?: return
        val vFile   = psiFile.virtualFile ?: return

        val text = psiFile.text
        val path = vFile.path
        val name = vFile.name
        val offset = editor.caretModel.offset
        val caretLine = editor.document.getLineNumber(offset) + 1
        val nameAtCaret = psiFile.findElementAt(offset)?.text?.trim()

        ProgressManager.getInstance().run(object : Task.Backgroundable(project, "Finding Igniter dependents…", true) {
            override fun run(indicator: ProgressIndicator) {
                indicator.isIndeterminate = true
                val model = IgniterModelService.getInstance(project).analyze(name, path, text).model

                val onLine = model.symbols.filter { it.line == caretLine }
                val target = onLine.firstOrNull { it.name == nameAtCaret } ?: onLine.firstOrNull()
                    ?: model.resolveRef(nameAtCaret ?: "", model.enclosingContract(caretLine)?.contract)

                val dependents = target?.let { model.usagesOf(it.name, it.contract) } ?: emptyList()

                ApplicationManager.getApplication().invokeLater {
                    when {
                        target == null ->
                            notify(project, "No Igniter node at the caret. Does the file compile?", NotificationType.WARNING)
                        dependents.isEmpty() ->
                            notify(project, "No nodes depend on '${target.name}'.", NotificationType.INFORMATION)
                        else ->
                            showPopup(project, editor, target, dependents, vFile)
                    }
                }
            }
        })
    }

    private fun showPopup(
        project: Project,
        editor: Editor,
        target: SymbolNode,
        dependents: List<SymbolNode>,
        vFile: com.intellij.openapi.vfs.VirtualFile
    ) {
        JBPopupFactory.getInstance()
            .createPopupChooserBuilder(dependents)
            .setTitle("Dependents of '${target.name}' (${dependents.size})")
            .setItemChosenCallback { dep ->
                val off = offsetOf(editor.document, dep.line, dep.col)
                OpenFileDescriptor(project, vFile, off).navigate(true)
            }
            .setRenderer(com.intellij.ui.SimpleListCellRenderer.create("") { node ->
                "${node.kind} ${node.name}" + (node.type?.let { ": ${it.render()}" } ?: "")
            })
            .createPopup()
            .showInBestPositionFor(editor)
    }

    private fun offsetOf(document: Document, line: Int, col: Int): Int {
        val lineIdx = (line - 1).coerceIn(0, (document.lineCount - 1).coerceAtLeast(0))
        val start = document.getLineStartOffset(lineIdx)
        val end = document.getLineEndOffset(lineIdx)
        return (start + (col - 1).coerceAtLeast(0)).coerceIn(start, end)
    }

    private fun notify(project: Project, message: String, type: NotificationType) {
        NotificationGroupManager.getInstance()
            .getNotificationGroup("Igniter Compiler")
            .createNotification("Igniter", message, type)
            .notify(project)
    }
}
