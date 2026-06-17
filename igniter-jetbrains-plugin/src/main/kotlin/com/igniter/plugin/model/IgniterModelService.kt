package com.igniter.plugin.model

import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.igniter.plugin.compiler.IgniterCompilerService
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
 * model reflect unsaved edits.
 */
@Service(Service.Level.PROJECT)
class IgniterModelService(@Suppress("unused") private val project: Project) {

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

            val result = IgniterCompilerService.getInstance().compile(src.toFile(), dir)
            val igapp = result.outputDir?.toFile()
            val model = if (igapp != null && igapp.isDirectory) parseModel(igapp) else IgniterModel.EMPTY
            Analysis(result.diagnostics, model)
        } catch (e: Exception) {
            log.warn("Model analysis failed for $path", e)
            Analysis(emptyList(), IgniterModel.EMPTY)
        }
    }

    /** Stable per-file cache directory (overwritten each refresh; one dir per path). */
    private fun cacheDirFor(path: String): Path {
        val key = Integer.toHexString(path.hashCode())
        val dir = Paths.get(System.getProperty("java.io.tmpdir"), "igniter-model", key)
        Files.createDirectories(dir)
        return dir
    }

    // -----------------------------------------------------------------------
    // Artifact parsing — joins sourcemap.json (position, sir_path) with
    // semantic_ir_program.json (inferred type, dependency edges) by node_id.
    // -----------------------------------------------------------------------

    private fun parseModel(igapp: File): IgniterModel {
        val sourceMapFile = File(igapp, "sourcemap.json").takeIf { it.exists() }
        val semanticIrFile = File(igapp, "semantic_ir_program.json").takeIf { it.exists() }
        if (sourceMapFile == null && semanticIrFile == null) return IgniterModel.EMPTY

        // semantic_ir: node_id -> (name, type, deps), plus module
        data class IrInfo(val name: String?, val type: IgniterType?, val deps: List<String>)
        val irByNode = HashMap<String, IrInfo>()
        var module: String? = null

        semanticIrFile?.let sem@{ f ->
            val root = parseObject(f) ?: return@sem
            module = root.stringOrNull("module")
            root.arrayOrNull("contracts")?.forEach { c ->
                val contract = c.asJsonObject
                sequenceOf("inputs", "nodes", "outputs").forEach { section ->
                    contract.arrayOrNull(section)?.forEach node@{ n ->
                        val node = n.asJsonObject
                        val id = node.stringOrNull("node_id") ?: return@node
                        irByNode[id] = IrInfo(
                            name = node.stringOrNull("name"),
                            type = parseType(node.getAsJsonObject2("type")),
                            deps = node.arrayOrNull("deps")
                                ?.mapNotNull { it.asString }
                                ?: emptyList()
                        )
                    }
                }
            }
        }

        val symbols = ArrayList<SymbolNode>()
        val seen = HashSet<String>()

        // sourcemap drives the symbol list (it carries positions + sir_path).
        sourceMapFile?.let src@{ f ->
            val root = parseObject(f) ?: return@src
            module = module ?: root.stringOrNull("module")
            root.arrayOrNull("nodes")?.forEach { n ->
                val node = n.asJsonObject
                val id = node.stringOrNull("node_id") ?: return@forEach
                val span = node.getAsJsonObject2("source_span")
                val ir = irByNode[id]
                symbols += symbol(
                    id = id,
                    kind = node.stringOrNull("kind"),
                    irName = ir?.name,
                    type = ir?.type,
                    line = span?.intOrNull("start_line") ?: 0,
                    col = span?.intOrNull("start_col") ?: 0,
                    sirPath = node.stringOrNull("sir_path"),
                    deps = ir?.deps ?: emptyList()
                )
                seen += id
            }
        }

        // Include any IR nodes the sourcemap didn't carry (no position).
        irByNode.forEach { (id, ir) ->
            if (id in seen) return@forEach
            symbols += symbol(id, null, ir.name, ir.type, 0, 0, null, ir.deps)
        }

        return IgniterModel(module, symbols, igapp, semanticIrFile, sourceMapFile)
    }

    /** Derives kind/contract/name from a node_id like `compute:Add.sum`, enriched by IR. */
    private fun symbol(
        id: String, kind: String?, irName: String?, type: IgniterType?,
        line: Int, col: Int, sirPath: String?, deps: List<String>
    ): SymbolNode {
        val colon = id.indexOf(':')
        val derivedKind = if (colon >= 0) id.substring(0, colon) else (kind ?: "node")
        val qualified = if (colon >= 0) id.substring(colon + 1) else id   // "Add.sum" or "Add"
        val dot = qualified.lastIndexOf('.')
        val contract = if (dot >= 0) qualified.substring(0, dot) else qualified
        val derivedName = if (dot >= 0) qualified.substring(dot + 1) else qualified
        return SymbolNode(
            nodeId = id,
            kind = kind ?: derivedKind,
            name = irName ?: derivedName,
            contract = contract,
            type = type,
            line = line,
            col = col,
            sirPath = sirPath,
            deps = deps
        )
    }

    private fun parseType(obj: JsonObject?): IgniterType? {
        val name = obj?.stringOrNull("name") ?: return null
        val params = obj.arrayOrNull("params")
            ?.mapNotNull { parseType(it.asJsonObject) }
            ?: emptyList()
        return IgniterType(name, params)
    }

    private fun parseObject(f: File): JsonObject? = try {
        JsonParser.parseString(f.readText()).takeIf { it.isJsonObject }?.asJsonObject
    } catch (e: Exception) {
        log.warn("Failed to parse ${f.name}", e); null
    }
}

// --- small null-tolerant Gson accessors ---

private fun JsonObject.stringOrNull(key: String) =
    get(key)?.takeIf { it.isJsonPrimitive }?.asString

private fun JsonObject.intOrNull(key: String) =
    get(key)?.takeIf { it.isJsonPrimitive }?.asInt

private fun JsonObject.arrayOrNull(key: String): JsonArray? =
    get(key)?.takeIf { it.isJsonArray }?.asJsonArray

private fun JsonObject.getAsJsonObject2(key: String): JsonObject? =
    get(key)?.takeIf { it.isJsonObject }?.asJsonObject
