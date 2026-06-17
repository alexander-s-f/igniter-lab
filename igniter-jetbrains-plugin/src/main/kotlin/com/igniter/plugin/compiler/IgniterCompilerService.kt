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
    val severity: OofSeverity,
    // LAB-COMPILER-MULTIFILE-SOURCE-MAP-P3 enrichment (LAB-JETBRAINS-…-MAPPING-P9):
    // per-file origin attached by the compiler to diagnostics with a merged line.
    // `mergedLine` is the raw report `line` when it was numeric (null when absent),
    // so the diagnostic mapper can also resolve origin via the source line map.
    val sourcePath: String? = null,
    val originalLine: Int? = null,
    val mergedLine: Int? = null
)

data class CompilationResult(
    val success: Boolean,
    val diagnostics: List<OofDiagnostic>,
    // Directory of the produced `<basename>.igapp` artifact bundle (may not exist
    // on hard failures). Used by ShowSemanticIRAction to locate semantic_ir_program.json.
    val outputDir: Path?,
    val rawOutput: String,
    // LAB-JETBRAINS-PROJECT-MODE-DIAGNOSTIC-MAPPING-P9: the multifile/project-mode
    // merged_line -> origin map (empty for single-file builds).
    val sourceLineMap: List<SourceLineMapEntry> = emptyList()
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
 *     is `rule` (not `code`). Parsing lives in [IgniterReportParser].
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
     * Compiles [sourceFile] alone with `igniter_compiler`
     * (`compile <sourceFile> --out OUT.igapp`).
     *
     * Used for the editor MODEL (navigation / inlays / structure), which must stay
     * in *editor* coordinates, and for the single-file path of files with no
     * non-stdlib imports. Import-aware compilation goes through [compileProject].
     *
     * @param outRoot directory under which `<basename>.igapp` is written. When null
     *   an ephemeral temp directory is used (the annotator path — no source-tree
     *   pollution). The compile action passes the source's own directory so the
     *   produced bundle is discoverable by ShowSemanticIRAction.
     */
    fun compile(sourceFile: File, outRoot: Path? = null): CompilationResult {
        val binary = resolveCompilerBinary() ?: return compilerNotFound()

        val root = outRoot ?: Files.createTempDirectory("igniter_out")
        val igapp = root.resolve("${sourceFile.nameWithoutExtension}.igapp")
        val command = listOf(binary, "compile", sourceFile.absolutePath, "--out", igapp.toString())
        return runCompile(command, root, igapp, sourceFile.nameWithoutExtension)
    }

    /**
     * LAB-JETBRAINS-PROJECT-MODE-DELEGATION-P7.
     * Compiles via the canonical compiler project mode + overlay — the compiler
     * owns project assembly and reads [overlayBuffer] in place of the on-disk
     * [overlayOriginal] (so unsaved editor text wins). The plugin supplies only
     * [projectRoot], [entryModule], and the overlay.
     *
     * The produced bundle is named `<outBaseName>.igapp` under [outRoot]; diagnostics
     * are read from whichever report layout the compiler writes (success bundle,
     * refusal sibling, or project-resolve sibling).
     */
    fun compileProject(
        projectRoot: String,
        entryModule: String,
        overlayOriginal: String,
        overlayBuffer: File,
        outRoot: Path,
        outBaseName: String,
    ): CompilationResult {
        val binary = resolveCompilerBinary() ?: return compilerNotFound()

        val igapp = outRoot.resolve("$outBaseName.igapp")
        val command = IgniterProjectModePlanner.buildCompileArgs(
            binary = binary,
            projectRoot = projectRoot,
            entryModule = entryModule,
            overlayOriginal = overlayOriginal,
            overlayBuffer = overlayBuffer.absolutePath,
            outIgapp = igapp.toString(),
        )
        return runCompile(command, outRoot, igapp, outBaseName)
    }

    private fun compilerNotFound(): CompilationResult = CompilationResult(
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

    /** Runs a prepared compiler [command] and parses the resulting report. */
    private fun runCompile(command: List<String>, root: Path, igapp: Path, base: String): CompilationResult {
        log.info("Running: ${command.joinToString(" ")}")
        return try {
            // Native binary: no interpreter/env plumbing needed.
            val process   = ProcessBuilder(command).redirectErrorStream(true).start()
            val rawOutput  = process.inputStream.bufferedReader().readText()
            val exitCode   = process.waitFor()

            val reportFile = locateReportFile(root, igapp, base)
            val reportText = if (reportFile != null && reportFile.exists()) reportFile.readText() else null
            val diagnostics = if (reportText != null) {
                IgniterReportParser.parseReport(reportText)
            } else {
                IgniterReportParser.parseFallbackOutput(rawOutput)
            }
            val sourceLineMap = reportText?.let { IgniterReportParser.parseSourceLineMap(it) } ?: emptyList()

            CompilationResult(
                success       = exitCode == 0,
                diagnostics   = diagnostics,
                outputDir     = igapp,
                rawOutput     = rawOutput,
                sourceLineMap = sourceLineMap
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
     * Locates `compilation_report.json` across both layouts the compiler produces:
     *   - success  -> inside `<basename>.igapp/`
     *   - refusal  -> sibling `<basename>.compilation_report.json` next to the bundle
     */
    private fun locateReportFile(root: Path, igapp: Path, base: String): File? {
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
}
