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
    // The canon diagnostic `rule` id (e.g. "OOF-TY0", "UNKNOWN"). Kept under the
    // `code` name so existing tooltip/structure consumers stay unchanged.
    val code: String,
    val message: String,
    val line: Int,
    val col: Int,
    val severity: OofSeverity
)

data class CompilationResult(
    val success: Boolean,
    val diagnostics: List<OofDiagnostic>,
    // Directory of the produced `<basename>.igapp` artifact bundle (may not exist
    // on hard failures). Used by ShowSemanticIRAction to locate semantic_ir_program.json.
    val outputDir: Path?,
    val rawOutput: String
)

/**
 * Bridges the editor to the lab Igniter compiler — the native Rust binary
 * `igniter_compiler` (igniter-lab/igniter-compiler), used in preference to the
 * Ruby `igc` CLI.
 *
 * Verified against the live `igniter_compiler` release binary:
 *   - Self-contained native binary; invoked `igniter_compiler compile SOURCE [SOURCE ...] --out OUT.igapp`.
 *     No interpreter / RUBYLIB plumbing required.
 *   - Prints a `compiler_result` JSON envelope to stdout every run; the canonical
 *     diagnostics live in the `compilation_report.json` it writes to disk.
 *   - Report layout (shared with `igc`):
 *       success  -> `<OUT>.igapp/compilation_report.json`            (inside the bundle)
 *       refusal  -> `<OUT-without-.igapp>.compilation_report.json`   (sibling file)
 *   - Diagnostic shape: `{ "rule", "severity", "message", "node", ... }` where the
 *     location is either a top-level `"line"` (Rust parse errors, no `col`) or a
 *     nested `"span": {"line","col"}` (Ruby/typecheck form). Both are handled; key
 *     is `rule` (not `code`).
 *
 * Lab-only: this wires the prototype to lab compiler evidence; it does not make the
 * editor a canonical authority on the language.
 */
@Service(Service.Level.APP)
class IgniterCompilerService {

    private val log = Logger.getInstance(IgniterCompilerService::class.java)

    companion object {
        @JvmStatic
        fun getInstance(): IgniterCompilerService =
            ApplicationManager.getApplication().getService(IgniterCompilerService::class.java)

        // Native lab compiler binary name (Rust, igniter-lab/igniter-compiler).
        private const val COMPILER_BINARY = "igniter_compiler"

        // OOF rule ids surfaced as warnings rather than hard errors when the
        // report does not already mark them so.
        private val WARNING_CODES = setOf("OOF-L3", "OOF-M2", "OOF-P2")
    }

    // -----------------------------------------------------------------------
    // Compiler binary resolution
    // -----------------------------------------------------------------------

    /**
     * Resolves the path to the native `igniter_compiler` binary, in order:
     *   1. configured path (Settings > Languages & Frameworks > Igniter)
     *   2. `IGNITER_COMPILER` env var (explicit binary path)
     *   3. `igniter_compiler` on PATH
     *   4. `IGNITER_LAB_HOME` env -> igniter-compiler/target/{release,debug}/igniter_compiler
     */
    fun resolveCompilerBinary(): String? {
        val configured = IgniterSettings.getInstance().compilerPath.trim()
        if (configured.isNotEmpty()) executableOrNull(configured)?.let { return it }

        System.getenv("IGNITER_COMPILER")?.let { executableOrNull(it)?.let { p -> return p } }

        System.getenv("PATH")?.split(File.pathSeparator)?.forEach { dir ->
            executableOrNull(File(dir, COMPILER_BINARY).path)?.let { return it }
        }

        System.getenv("IGNITER_LAB_HOME")?.let { home ->
            for (profile in listOf("release", "debug")) {
                val candidate = File(home, "igniter-compiler/target/$profile/$COMPILER_BINARY")
                executableOrNull(candidate.path)?.let { return it }
            }
        }
        return null
    }

    private fun executableOrNull(path: String): String? {
        val f = File(path)
        return if (f.exists() && f.canExecute()) f.absolutePath else null
    }

    // -----------------------------------------------------------------------
    // Compile
    // -----------------------------------------------------------------------

    /**
     * Compiles [sourceFile] with `igc`.
     *
     * @param outRoot directory under which `<basename>.igapp` is written. When null
     *   an ephemeral temp directory is used (the annotator path — no source-tree
     *   pollution). The compile action passes the source's own directory so the
     *   produced bundle is discoverable by ShowSemanticIRAction.
     */
    fun compile(sourceFile: File, outRoot: Path? = null): CompilationResult {
        val binary = resolveCompilerBinary()
            ?: return CompilationResult(
                success = false,
                diagnostics = listOf(
                    OofDiagnostic(
                        code = "PLUGIN-001",
                        message = "igniter_compiler not found. Set its path in " +
                            "Settings > Languages & Frameworks > Igniter, put it on PATH, or set " +
                            "IGNITER_COMPILER / IGNITER_LAB_HOME.",
                        line = 1, col = 1, severity = OofSeverity.ERROR
                    )
                ),
                outputDir = null,
                rawOutput = "igniter_compiler not found"
            )

        val root = outRoot ?: Files.createTempDirectory("igniter_out")
        val igapp = root.resolve("${sourceFile.nameWithoutExtension}.igapp")
        val command = listOf(binary, "compile", sourceFile.absolutePath, "--out", igapp.toString())
        log.info("Running: ${command.joinToString(" ")}")

        return try {
            // Native binary: no interpreter/env plumbing needed.
            val process   = ProcessBuilder(command).redirectErrorStream(true).start()
            val rawOutput  = process.inputStream.bufferedReader().readText()
            val exitCode   = process.waitFor()

            val reportFile = locateReportFile(root, igapp, sourceFile)
            val diagnostics = if (reportFile != null && reportFile.exists()) {
                parseReport(reportFile.readText())
            } else {
                parseFallbackOutput(rawOutput)
            }

            CompilationResult(
                success     = exitCode == 0,
                diagnostics = diagnostics,
                outputDir   = igapp,
                rawOutput   = rawOutput
            )
        } catch (e: Exception) {
            log.warn("Compiler invocation failed", e)
            CompilationResult(
                success     = false,
                diagnostics = listOf(
                    OofDiagnostic(
                        code     = "PLUGIN-002",
                        message  = "Failed to invoke igniter_compiler: ${e.message}",
                        line     = 1, col = 1, severity = OofSeverity.ERROR
                    )
                ),
                outputDir   = null,
                rawOutput   = e.message ?: "unknown error"
            )
        }
    }

    /**
     * Locates `compilation_report.json` across both layouts `igc` produces:
     *   - success  -> inside `<basename>.igapp/`
     *   - refusal  -> sibling `<basename>.compilation_report.json` next to the bundle
     */
    private fun locateReportFile(root: Path, igapp: Path, sourceFile: File): File? {
        val base = sourceFile.nameWithoutExtension

        // Success layout: report inside the bundle.
        val inside = igapp.resolve("compilation_report.json").toFile()
        if (inside.exists()) return inside

        // Refusal layout: sibling file next to the bundle.
        val sibling = root.resolve("$base.compilation_report.json").toFile()
        if (sibling.exists()) return sibling

        // Fallback: any *.compilation_report.json directly under the out root.
        root.toFile().listFiles { f -> f.isFile && f.name.endsWith(".compilation_report.json") }
            ?.firstOrNull()
            ?.let { return it }

        return null
    }

    // -----------------------------------------------------------------------
    // compilation_report.json parsing — pure stdlib, no JSON library
    // -----------------------------------------------------------------------

    /**
     * Minimal parser extracting diagnostic objects from compilation_report.json.
     *
     * Canon shape (verified live):
     * {
     *   "diagnostics": [
     *     { "rule": "OOF-TY0", "message": "...", "severity": "error",
     *       "span": { "line": 5, "col": 3 } | null, ... }
     *   ]
     * }
     */
    private fun parseReport(json: String): List<OofDiagnostic> {
        val result = mutableListOf<OofDiagnostic>()
        val arrayContent = extractArrayContent(json, "diagnostics")
            ?: extractArrayContent(json, "errors")
            ?: return result

        for (objStr in splitJsonObjects(arrayContent)) {
            // Canon uses `rule`; tolerate `code` for forward/legacy compatibility.
            val code     = extractString(objStr, "rule") ?: extractString(objStr, "code") ?: continue
            val message  = extractString(objStr, "message") ?: extractString(objStr, "msg") ?: ""
            val (line, col) = extractLineCol(objStr)
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

    /**
     * Extracts (line, col) for a diagnostic, supporting both compiler forms:
     *   - nested `"span": { "line", "col" }` (Ruby `igc` / typecheck diagnostics)
     *   - top-level `"line"` with no `col` (Rust `igniter_compiler` parse errors)
     * Defaults to (1, 1) when neither is present so the annotation still lands.
     */
    private fun extractLineCol(obj: String): Pair<Int, Int> {
        extractObjectContent(obj, "span")?.let { span ->
            val line = extractInt(span, "line") ?: 1
            val col  = extractInt(span, "col") ?: extractInt(span, "column") ?: 1
            return line to col
        }
        val line = extractInt(obj, "line") ?: 1
        val col  = extractInt(obj, "col") ?: extractInt(obj, "column") ?: 1
        return line to col
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

    /**
     * Returns the brace-delimited content of object-valued [key], or null when the
     * value is absent or `null` (e.g. `"span": null`).
     */
    private fun extractObjectContent(json: String, key: String): String? {
        val keyPattern = Regex(""""$key"\s*:\s*\{""")
        val match = keyPattern.find(json) ?: return null
        val start = match.range.last // index of '{'
        var depth = 0
        var i = start
        while (i < json.length) {
            when (json[i]) {
                '{' -> depth++
                '}' -> { depth--; if (depth == 0) return json.substring(start + 1, i) }
                '"' -> {
                    i++
                    while (i < json.length && json[i] != '"') {
                        if (json[i] == '\\') i++
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

    /**
     * Last-resort scan of stdout when no report file was produced. `igc` prints a
     * `compiler_result` envelope to stdout; we look for rule ids with a line hint.
     */
    private fun parseFallbackOutput(raw: String): List<OofDiagnostic> {
        val pattern = Regex("""(OOF-[A-Z0-9]+).*?line[":\s]+(\d+)""", RegexOption.IGNORE_CASE)
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
