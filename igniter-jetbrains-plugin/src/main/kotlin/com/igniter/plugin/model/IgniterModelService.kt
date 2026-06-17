package com.igniter.plugin.model

import com.igniter.plugin.compiler.IgniterCompilerService
import com.igniter.plugin.compiler.IgniterImportCompilePlanner
import com.igniter.plugin.compiler.OofDiagnostic
import com.intellij.openapi.components.Service
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.Project
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.util.concurrent.ConcurrentHashMap

/**
 * Per-project analysis cache: compiles a `.ig` file's *editor text* once per
 * content hash and exposes both compiler diagnostics and the joined semantic
 * [IgniterModel]. All "smart" DX surfaces (navigation, hints, structure) read
 * from here so they stay consistent with the lab compiler's authoritative output.
 *
 * Compiling the in-memory text (not the on-disk file) means diagnostics and the
 * model reflect unsaved edits. The artifact join itself lives in the pure
 * [IgniterModelParser] so it can be proven without an IDE fixture.
 */
@Service(Service.Level.PROJECT)
class IgniterModelService(private val project: Project) {

    private val log = Logger.getInstance(IgniterModelService::class.java)

    /** Result of one compile: diagnostics for the annotator, model for navigation/hints. */
    data class Analysis(val diagnostics: List<OofDiagnostic>, val model: IgniterModel)

    private data class Entry(val contentHash: Int, val analysis: Analysis)

    // Keyed by the file's path. Holds the most recent analysis per file.
    private val cache = ConcurrentHashMap<String, Entry>()

    companion object {
        @JvmStatic
        fun getInstance(project: Project): IgniterModelService =
            project.getService(IgniterModelService::class.java)
    }

    /** Cached analysis if [text]'s hash still matches, else null. Cheap; any thread. */
    fun cached(path: String, text: String): Analysis? =
        cache[path]?.takeIf { it.contentHash == text.hashCode() }?.analysis

    /**
     * Returns the analysis for [text], compiling if needed. BLOCKING (spawns the
     * compiler + reads artifacts) — call on a background thread.
     */
    fun analyze(fileName: String, path: String, text: String): Analysis {
        cached(path, text)?.let { return it }
        val analysis = build(fileName, path, text)
        cache[path] = Entry(text.hashCode(), analysis)
        return analysis
    }

    fun model(fileName: String, path: String, text: String): IgniterModel =
        analyze(fileName, path, text).model

    // -----------------------------------------------------------------------

    private fun build(fileName: String, path: String, text: String): Analysis {
        return try {
            val dir = cacheDirFor(path)
            val base = fileName.removeSuffix(".ig").ifEmpty { "source" }
            val src = dir.resolve("$base.ig")
            Files.write(src, text.toByteArray(StandardCharsets.UTF_8))

            val compiler = IgniterCompilerService.getInstance()

            // The model (navigation / inlays / structure) is always derived from the
            // current file compiled alone, so its line/col stay in *editor*
            // coordinates. A failing standalone compile yields no artifacts → the
            // model is EMPTY, exactly as before this card.
            val modelResult = compiler.compile(src.toFile(), dir)
            val igapp = modelResult.outputDir?.toFile()
            val model = if (igapp != null && igapp.isDirectory) IgniterModelParser.parse(igapp) else IgniterModel.EMPTY

            // Diagnostics become import-aware: if the current file imports resolvable
            // project modules, compile it *together with* those modules so the
            // compiler resolves cross-module declarations (no false OOF-P1) and is the
            // authority on genuinely missing imports (OOF-IMP*). Falls back to the
            // standalone diagnostics when there are no resolvable imports.
            val importedSources = resolveImportedSources(path, text)
            val diagnostics = if (importedSources.isNotEmpty()) {
                val importsDir = Files.createDirectories(dir.resolve("imports"))
                compiler.compile(src.toFile(), importsDir, importedSources).diagnostics
            } else {
                modelResult.diagnostics
            }

            Analysis(diagnostics, model)
        } catch (e: Exception) {
            log.warn("Model analysis failed for $path", e)
            Analysis(emptyList(), IgniterModel.EMPTY)
        }
    }

    /**
     * On-disk `.ig` files for the current file's (transitively) imported project
     * modules, or empty when the file has no non-stdlib imports or no project root
     * is known. The current file is excluded from the scan so its in-editor text
     * remains the single source of truth for its own module.
     */
    private fun resolveImportedSources(path: String, text: String): List<File> {
        val imports = IgniterImportCompilePlanner.importedModules(text)
        if (imports.isEmpty()) return emptyList()
        val root = project.basePath?.let { Paths.get(it) } ?: return emptyList()
        val index = IgniterImportCompilePlanner.scanProject(root, excludePath = path)
        val module = IgniterImportCompilePlanner.moduleNameOf(text)
        return IgniterImportCompilePlanner.resolve(module, imports, index).map(::File)
    }

    /** Stable per-file cache directory (overwritten each refresh; one dir per path). */
    private fun cacheDirFor(path: String): Path {
        val key = Integer.toHexString(path.hashCode())
        val dir = Paths.get(System.getProperty("java.io.tmpdir"), "igniter-model", key)
        Files.createDirectories(dir)
        return dir
    }
}
