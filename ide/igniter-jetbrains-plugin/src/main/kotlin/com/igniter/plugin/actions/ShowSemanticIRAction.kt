package com.igniter.plugin.actions

import com.igniter.plugin.lang.IgniterFile
import com.intellij.notification.NotificationGroupManager
import com.intellij.notification.NotificationType
import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.actionSystem.CommonDataKeys
import com.intellij.openapi.fileEditor.FileEditorManager
import com.intellij.openapi.vfs.LocalFileSystem
import java.io.File
import java.nio.file.Paths

/**
 * Opens the `semantic_ir_program.json` artifact produced by the Igniter compiler
 * for the currently open .ig file.  The JSON file is opened with the built-in
 * JSON editor so it gets full syntax highlighting and folding.
 *
 * Convention: the compiler writes to `<source_dir>/<basename>.igapp/semantic_ir_program.json`
 * or falls back to any `*.igapp` directory found next to the source file.
 */
class ShowSemanticIRAction : AnAction() {

    override fun update(e: AnActionEvent) {
        val psiFile = e.getData(CommonDataKeys.PSI_FILE)
        e.presentation.isEnabledAndVisible = psiFile is IgniterFile
    }

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val psiFile = e.getData(CommonDataKeys.PSI_FILE) as? IgniterFile ?: return
        val vFile   = psiFile.virtualFile ?: return
        val sourceFile = File(vFile.path)

        val irFile = findSemanticIR(sourceFile)
        if (irFile == null || !irFile.exists()) {
            NotificationGroupManager.getInstance()
                .getNotificationGroup("Igniter Compiler")
                .createNotification(
                    "Igniter",
                    "No semantic_ir_program.json found for ${sourceFile.name}. Compile the file first (Ctrl+Shift+F9).",
                    NotificationType.WARNING
                ).notify(project)
            return
        }

        val vIrFile = LocalFileSystem.getInstance().refreshAndFindFileByIoFile(irFile)
        if (vIrFile == null) {
            NotificationGroupManager.getInstance()
                .getNotificationGroup("Igniter Compiler")
                .createNotification("Igniter", "Could not open ${irFile.path}", NotificationType.ERROR)
                .notify(project)
            return
        }

        FileEditorManager.getInstance(project).openFile(vIrFile, true)
    }

    private fun findSemanticIR(sourceFile: File): File? {
        val baseName  = sourceFile.nameWithoutExtension
        val parentDir = sourceFile.parentFile ?: return null

        // Primary convention: <basename>.igapp/semantic_ir_program.json
        val primary = Paths.get(parentDir.path, "$baseName.igapp", "semantic_ir_program.json").toFile()
        if (primary.exists()) return primary

        // Fallback: any *.igapp directory
        parentDir.listFiles { f -> f.isDirectory && f.name.endsWith(".igapp") }
            ?.forEach { igapp ->
                val candidate = File(igapp, "semantic_ir_program.json")
                if (candidate.exists()) return candidate
            }

        return null
    }
}
