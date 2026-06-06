package com.igniter.plugin.compiler

import com.igniter.plugin.settings.IgniterSettings
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.components.Service
import com.intellij.openapi.diagnostic.Logger
import java.io.File
import java.nio.file.Files
import java.nio.file.Path

enum class OofSeverity { ERROR, WARNING, INFO }

data class OofDiagnostic(
    val code: String,
    val message: String,
    val line: Int,
    val col: Int,
    val severity: OofSeverity
)

data class CompilationResult(
    val success: Boolean,
    val diagnostics: List<OofDiagnostic>,
    val outputDir: Path?,
    val rawOutput: String
)

@Service(Service.Level.APP)
class IgniterCompilerService {

    private val log = Logger.getInstance(IgniterCompilerService::class.java)

    companion object {
        @JvmStatic
        fun getInstance(): IgniterCompilerService =
            ApplicationManager.getApplication().getService(IgniterCompilerService::class.java)

        // OOF error codes treated as warnings rather than hard errors
        private val WARNING_CODES = setOf("OOF-L3", "OOF-M2", "OOF-P2")
    }

    // -----------------------------------------------------------------------
    // Compiler binary resolution
    // -----------------------------------------------------------------------

    fun resolveCompilerBinary(): String? {
        val settings = IgniterSettings.getInstance()
        val configured = settings.compilerPath.trim()
        if (configured.isNotEmpty()) {
            val f = File(configured)
            if (f.exists() && f.canExecute()) return configured
        }

        val pathEnv = System.getenv("PATH") ?: return null
        for (dir in pathEnv.split(File.pathSeparator)) {
            val candidate = File(dir, "igniter_compiler")
            if (candidate.exists() && candidate.canExecute()) return candidate.absolutePath
        }
        return null
    }

    // -----------------------------------------------------------------------
    // Compile
    // -----------------------------------------------------------------------

    fun compile(sourceFile: File): CompilationResult {
        val binary = resolveCompilerBinary()
            ?: return CompilationResult(
                success = false,
                diagnostics = listOf(
                    OofDiagnostic(
                        code = "PLUGIN-001",
                        message = "igniter_compiler binary not found. Configure the path in " +
                            "Settings > Languages & Frameworks > Igniter.",
                        line = 1, col = 1, severity = OofSeverity.ERROR
                    )
                ),
                outputDir = null,
                rawOutput = "igniter_compiler not found"
            )

        val outDir = Files.createTempDirectory("igniter_out")
        val command = listOf(binary, "compile", sourceFile.absolutePath, "--out", outDir.toString())
        log.info("Running: ${command.joinToString(" ")}")

        return try {
            val process = ProcessBuilder(command)
                .redirectErrorStream(true)
                .start()

            val rawOutput = process.inputStream.bufferedReader().readText()
            val exitCode  = process.waitFor()

            // Primary: look for compilation_report.json inside the .igapp output directory
            val reportFile = locateReportFile(outDir, sourceFile)
            val diagnostics = if (reportFile != null && reportFile.exists()) {
                parseReport(reportFile.readText())
            } else {
                parseFallbackOutput(rawOutput)
            }

            CompilationResult(
                success     = exitCode == 0,
                diagnostics = diagnostics,
                outputDir   = outDir,
                rawOutput   = rawOutput
            )
        } catch (e: Exception) {
            log.warn("Compiler invocation failed", e)
            CompilationResult(
                success     = false,
                diagnostics = listOf(
                    OofDiagnostic(
                        code     = "PLUGIN-002",
                        message  = "Failed to invoke compiler: ${e.message}",
                        line     = 1, col = 1, severity = OofSeverity.ERROR
                    )
                ),
                outputDir   = null,
                rawOutput   = e.message ?: "unknown error"
            )
        }
    }

    private fun locateReportFile(outDir: Path, sourceFile: File): File? {
        // <outDir>/<basename>.igapp/compilation_report.json
        val primary = outDir.resolve("${sourceFile.nameWithoutExtension}.igapp")
            .resolve("compilation_report.json").toFile()
        if (primary.exists()) return primary

        // Any .igapp directory in outDir
        outDir.toFile().listFiles { f -> f.isDirectory && f.name.endsWith(".igapp") }
            ?.forEach { dir ->
                val candidate = File(dir, "compilation_report.json")
                if (candidate.exists()) return candidate
            }
        return null
    }

    // -----------------------------------------------------------------------
    // compilation_report.json parsing — pure stdlib, no JSON library
    // -----------------------------------------------------------------------

    /**
     * Minimal JSON array parser that extracts diagnostic objects from
     * compilation_report.json without an external library.
     *
     * Expected shape (either "errors" or "diagnostics" key):
     * {
     *   "errors": [
     *     { "code": "OOF-L1", "message": "...", "line": 5, "col": 3, "severity": "error" },
     *     ...
     *   ]
     * }
     */
    private fun parseReport(json: String): List<OofDiagnostic> {
        val result = mutableListOf<OofDiagnostic>()
        // Find the first array that corresponds to errors / diagnostics
        val arrayContent = extractArrayContent(json, "errors")
            ?: extractArrayContent(json, "diagnostics")
            ?: return result

        // Split into individual objects — naive but sufficient for flat arrays
        for (objStr in splitJsonObjects(arrayContent)) {
            val code     = extractString(objStr, "code")    ?: continue
            val message  = extractString(objStr, "message") ?: extractString(objStr, "msg") ?: ""
            val line     = extractInt(objStr, "line")       ?: 1
            val col      = extractInt(objStr, "col")        ?: extractInt(objStr, "column") ?: 1
            val rawSev   = extractString(objStr, "severity")?.lowercase() ?: "error"
            val severity = when {
                code in WARNING_CODES || rawSev == "warning" || rawSev == "warn" -> OofSeverity.WARNING
                rawSev == "info"                                                  -> OofSeverity.INFO
                else                                                              -> OofSeverity.ERROR
            }
            result += OofDiagnostic(code, message, line, col, severity)
        }
        return result
    }

    private fun extractArrayContent(json: String, key: String): String? {
        val keyPattern = Regex(""""$key"\s*:\s*\[""")
        val match = keyPattern.find(json) ?: return null
        val start = match.range.last // index of '['
        var depth = 0
        var i = start
        while (i < json.length) {
            when (json[i]) {
                '[' -> depth++
                ']' -> { depth--; if (depth == 0) return json.substring(start + 1, i) }
                '"' -> {
                    i++ // skip opening quote
                    while (i < json.length && json[i] != '"') {
                        if (json[i] == '\\') i++ // skip escape
                        i++
                    }
                }
            }
            i++
        }
        return null
    }

    private fun splitJsonObjects(arrayContent: String): List<String> {
        val objects = mutableListOf<String>()
        var depth = 0
        var start = -1
        var inString = false
        var i = 0
        while (i < arrayContent.length) {
            val c = arrayContent[i]
            when {
                c == '"' && !inString -> inString = true
                c == '"' && inString && (i == 0 || arrayContent[i - 1] != '\\') -> inString = false
                !inString && c == '{' -> {
                    if (depth == 0) start = i
                    depth++
                }
                !inString && c == '}' -> {
                    depth--
                    if (depth == 0 && start >= 0) {
                        objects += arrayContent.substring(start, i + 1)
                        start = -1
                    }
                }
            }
            i++
        }
        return objects
    }

    private fun extractString(obj: String, key: String): String? {
        val re = Regex(""""$key"\s*:\s*"((?:[^"\\]|\\.)*)"""")
        return re.find(obj)?.groupValues?.get(1)
    }

    private fun extractInt(obj: String, key: String): Int? {
        val re = Regex(""""$key"\s*:\s*(\d+)""")
        return re.find(obj)?.groupValues?.get(1)?.toIntOrNull()
    }

    private fun parseFallbackOutput(raw: String): List<OofDiagnostic> {
        val pattern = Regex("""(OOF-[A-Z0-9]+).*?line[:\s]+(\d+)""", RegexOption.IGNORE_CASE)
        return raw.lines().mapNotNull { line ->
            val m = pattern.find(line) ?: return@mapNotNull null
            OofDiagnostic(
                code     = m.groupValues[1],
                message  = line.trim(),
                line     = m.groupValues[2].toIntOrNull() ?: 1,
                col      = 1,
                severity = if (m.groupValues[1] in WARNING_CODES) OofSeverity.WARNING else OofSeverity.ERROR
            )
        }
    }
}
