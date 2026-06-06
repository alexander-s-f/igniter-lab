package com.igniter.plugin.actions

import com.igniter.plugin.compiler.IgniterCompilerService
import com.igniter.plugin.compiler.OofSeverity
import com.igniter.plugin.lang.IgniterFile
import com.intellij.notification.NotificationGroupManager
import com.intellij.notification.NotificationType
import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.actionSystem.CommonDataKeys
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task
import com.intellij.openapi.project.Project
import java.io.File

class CompileIgniterFileAction : AnAction() {

    override fun update(e: AnActionEvent) {
        val psiFile = e.getData(CommonDataKeys.PSI_FILE)
        e.presentation.isEnabledAndVisible = psiFile is IgniterFile
    }

    override fun actionPerformed(e: AnActionEvent) {
        val project  = e.project ?: return
        val psiFile  = e.getData(CommonDataKeys.PSI_FILE) as? IgniterFile ?: return
        val vFile    = psiFile.virtualFile ?: return
        val ioFile   = File(vFile.path)

        ProgressManager.getInstance().run(object : Task.Backgroundable(project, "Compiling Igniter file…", true) {
            override fun run(indicator: ProgressIndicator) {
                indicator.isIndeterminate = true
                val result = IgniterCompilerService.getInstance().compile(ioFile)

                ApplicationManager.getApplication().invokeLater {
                    showResult(project, ioFile.name, result.success, result.diagnostics.size,
                        result.diagnostics.count { it.severity == OofSeverity.ERROR },
                        result.rawOutput)
                }
            }
        })
    }

    private fun showResult(
        project: Project,
        fileName: String,
        success: Boolean,
        total: Int,
        errors: Int,
        rawOutput: String
    ) {
        val group = NotificationGroupManager.getInstance()
            .getNotificationGroup("Igniter Compiler")

        if (success) {
            group.createNotification(
                "Igniter Compiler",
                "$fileName compiled successfully ($total diagnostic(s))",
                NotificationType.INFORMATION
            ).notify(project)
        } else {
            val preview = if (rawOutput.length > 400) rawOutput.take(400) + "…" else rawOutput
            group.createNotification(
                "Igniter Compiler",
                "$fileName: $errors error(s). $preview",
                NotificationType.ERROR
            ).notify(project)
        }
    }
}
