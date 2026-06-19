package com.igniter.plugin.actions

import com.igniter.plugin.compiler.IgniterCompilerService
import com.igniter.plugin.compiler.IgniterProjectModePlanner
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
                // Explicit compile: write the .igapp bundle next to the source so
                // "Show Semantic IR" can find semantic_ir_program.json afterwards.
                val outRoot = ioFile.parentFile?.toPath()
                // Import-aware via compiler project mode + overlay (P7): when the
                // file declares a module and has non-stdlib imports (and lives inside
                // the project root), the compiler resolves the import closure. The
                // saved file is its own overlay buffer. Otherwise the unchanged
                // single-file compile runs.
                val result = compileFile(project, vFile.path, ioFile, outRoot)

                // First error message reads better than the raw JSON envelope the
                // native compiler prints to stdout.
                val firstError = result.diagnostics
                    .firstOrNull { it.severity == OofSeverity.ERROR }
                    ?.let { "[${it.code}] ${it.message}" }
                    ?: result.rawOutput.take(200)

                ApplicationManager.getApplication().invokeLater {
                    showResult(project, ioFile.name, result.success, result.diagnostics.size,
                        result.diagnostics.count { it.severity == OofSeverity.ERROR },
                        firstError)
                }
            }
        })
    }

    /**
     * Compiles [ioFile] through compiler project mode + overlay when it declares a
     * module and has non-stdlib imports and lives inside the project root; otherwise
     * the unchanged single-file compile. The saved on-disk file is used as its own
     * overlay buffer (content == disk), so both paths share the project-mode invocation.
     */
    private fun compileFile(
        project: Project,
        path: String,
        ioFile: File,
        outRoot: java.nio.file.Path?
    ): com.igniter.plugin.compiler.CompilationResult {
        val service = IgniterCompilerService.getInstance()
        val text = runCatching { ioFile.readText() }.getOrNull()
        val entry = text?.let { IgniterProjectModePlanner.entryModuleForProjectMode(it) }
        val root = project.basePath
        if (entry != null && root != null && outRoot != null && isInsideRoot(path, root)) {
            return service.compileProject(
                projectRoot = root,
                entryModule = entry,
                overlayOriginal = path,
                overlayBuffer = ioFile,
                outRoot = outRoot,
                outBaseName = ioFile.nameWithoutExtension,
            )
        }
        return service.compile(ioFile, outRoot)
    }

    /** True when [path] is lexically inside the project [root] (overlay precondition). */
    private fun isInsideRoot(path: String, root: String): Boolean =
        runCatching {
            val p = java.nio.file.Paths.get(path).toAbsolutePath().normalize()
            val r = java.nio.file.Paths.get(root).toAbsolutePath().normalize()
            p.startsWith(r)
        }.getOrDefault(false)

    private fun showResult(
        project: Project,
        fileName: String,
        success: Boolean,
        total: Int,
        errors: Int,
        detail: String
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
            group.createNotification(
                "Igniter Compiler",
                "$fileName: $errors error(s). $detail",
                NotificationType.ERROR
            ).notify(project)
        }
    }
}
