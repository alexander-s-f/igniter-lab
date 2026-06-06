package com.igniter.plugin.toolwindow

import com.igniter.plugin.compiler.CompilationResult
import com.igniter.plugin.compiler.IgniterCompilerService
import com.igniter.plugin.compiler.OofSeverity
import com.igniter.plugin.lang.IgniterFile
import com.intellij.openapi.fileEditor.FileEditorManagerEvent
import com.intellij.openapi.fileEditor.FileEditorManagerListener
import com.intellij.openapi.progress.ProgressIndicator
import com.intellij.openapi.progress.ProgressManager
import com.intellij.openapi.progress.Task
import com.intellij.openapi.project.DumbAware
import com.intellij.openapi.project.Project
import com.intellij.openapi.vfs.VirtualFile
import com.intellij.openapi.wm.ToolWindow
import com.intellij.openapi.wm.ToolWindowFactory
import com.intellij.psi.PsiManager
import com.intellij.ui.components.JBScrollPane
import com.intellij.ui.components.JBTabbedPane
import com.intellij.ui.components.JBTextArea
import java.awt.BorderLayout
import java.io.File
import javax.swing.JButton
import javax.swing.JPanel
import javax.swing.SwingUtilities

class IgniterToolWindowFactory : ToolWindowFactory, DumbAware {

    override fun createToolWindowContent(project: Project, toolWindow: ToolWindow) {
        val contentManager = toolWindow.contentManager

        // Three panels
        val compilerOutputPanel  = CompilerOutputPanel(project)
        val observationsPanel    = ObservationsPanel()
        val semanticIRPanel      = SemanticIRPanel()

        val tabs = JBTabbedPane()
        tabs.addTab("Compiler Output",  compilerOutputPanel.component)
        tabs.addTab("Observations",     observationsPanel.component)
        tabs.addTab("Semantic IR",      semanticIRPanel.component)

        val content = contentManager.factory.createContent(tabs, "", false)
        contentManager.addContent(content)

        // Listen for editor focus changes and refresh
        project.messageBus.connect(toolWindow.disposable)
            .subscribe(FileEditorManagerListener.FILE_EDITOR_MANAGER, object : FileEditorManagerListener {
                override fun selectionChanged(event: FileEditorManagerEvent) {
                    val vf = event.newFile ?: return
                    val psi = PsiManager.getInstance(project).findFile(vf)
                    if (psi !is IgniterFile) return
                    compilerOutputPanel.refresh(project, vf)
                    observationsPanel.refresh(vf)
                    semanticIRPanel.refresh(vf)
                }
            })
    }
}

// ---------------------------------------------------------------------------
// Compiler Output tab
// ---------------------------------------------------------------------------

class CompilerOutputPanel(private val project: Project) {
    private val textArea = JBTextArea().apply { isEditable = false; lineWrap = true; wrapStyleWord = true }
    private val refreshBtn = JButton("Compile Now")
    private var currentVFile: VirtualFile? = null

    val component: JPanel = JPanel(BorderLayout()).apply {
        add(refreshBtn, BorderLayout.NORTH)
        add(JBScrollPane(textArea), BorderLayout.CENTER)
    }

    init {
        refreshBtn.addActionListener {
            currentVFile?.let { refresh(project, it) }
        }
    }

    fun refresh(project: Project, vFile: VirtualFile) {
        currentVFile = vFile
        textArea.text = "Compiling…"

        ProgressManager.getInstance().run(object : Task.Backgroundable(project, "Igniter: compiling", true) {
            override fun run(indicator: ProgressIndicator) {
                val result = IgniterCompilerService.getInstance().compile(File(vFile.path))
                SwingUtilities.invokeLater { displayResult(result) }
            }
        })
    }

    private fun displayResult(result: CompilationResult) {
        val sb = StringBuilder()
        sb.appendLine(if (result.success) "✓ Compilation succeeded" else "✗ Compilation failed")
        sb.appendLine()
        if (result.diagnostics.isEmpty()) {
            sb.appendLine("No diagnostics.")
        } else {
            for (d in result.diagnostics) {
                val icon = when (d.severity) {
                    OofSeverity.ERROR   -> "ERROR  "
                    OofSeverity.WARNING -> "WARN   "
                    OofSeverity.INFO    -> "INFO   "
                }
                sb.appendLine("$icon [${d.code}] line ${d.line}:${d.col}  ${d.message}")
            }
        }
        if (result.rawOutput.isNotBlank()) {
            sb.appendLine()
            sb.appendLine("--- Raw output ---")
            sb.appendLine(result.rawOutput)
        }
        textArea.text = sb.toString()
        textArea.caretPosition = 0
    }
}

// ---------------------------------------------------------------------------
// Observations tab
// ---------------------------------------------------------------------------

class ObservationsPanel {
    private val textArea = JBTextArea().apply { isEditable = false; lineWrap = true; wrapStyleWord = true }

    val component: JPanel = JPanel(BorderLayout()).apply {
        add(JBScrollPane(textArea), BorderLayout.CENTER)
    }

    fun refresh(vFile: VirtualFile) {
        val sourceFile = File(vFile.path)
        val baseName   = sourceFile.nameWithoutExtension
        val parentDir  = sourceFile.parentFile ?: return

        // Look for emit / EMIT_OBS entries in compilation_report.json
        val reportFile = File(parentDir, "$baseName.igapp/compilation_report.json")
        if (!reportFile.exists()) {
            textArea.text = "No compilation report found. Compile the file first."
            return
        }

        try {
            val json = reportFile.readText()
            val obs  = extractObservations(json)
            if (obs.isEmpty()) {
                textArea.text = "No observations (EMIT_OBS) recorded."
            } else {
                textArea.text = obs.joinToString("\n")
            }
        } catch (e: Exception) {
            textArea.text = "Error reading observations: ${e.message}"
        }
        textArea.caretPosition = 0
    }

    private fun extractObservations(json: String): List<String> {
        // Simple regex extraction — no JSON library dependency at this layer
        val re = Regex(""""(EMIT_OBS[^"]*)"[^:]*:\s*"([^"]*)"""")
        return re.findAll(json).map { "${it.groupValues[1]}: ${it.groupValues[2]}" }.toList()
    }
}

// ---------------------------------------------------------------------------
// Semantic IR tab
// ---------------------------------------------------------------------------

class SemanticIRPanel {
    private val textArea = JBTextArea().apply { isEditable = false; lineWrap = false }

    val component: JPanel = JPanel(BorderLayout()).apply {
        add(JBScrollPane(textArea), BorderLayout.CENTER)
    }

    fun refresh(vFile: VirtualFile) {
        val sourceFile = File(vFile.path)
        val baseName   = sourceFile.nameWithoutExtension
        val parentDir  = sourceFile.parentFile ?: return

        val irFile = File(parentDir, "$baseName.igapp/semantic_ir_program.json")
        if (!irFile.exists()) {
            textArea.text = "No semantic IR found. Compile the file first."
            return
        }

        try {
            textArea.text = irFile.readText()
            textArea.caretPosition = 0
        } catch (e: Exception) {
            textArea.text = "Error reading semantic IR: ${e.message}"
        }
    }
}
