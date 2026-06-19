package com.igniter.plugin.model

import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.io.File

/**
 * Pure (IntelliJ-free) builder of an [IgniterModel] from a compiled `.igapp`
 * bundle. Joins `sourcemap.json` (position + sir_path) with
 * `semantic_ir_program.json` (inferred type + dependency edges) by `node_id`.
 *
 * Kept separate from [IgniterModelService] so the semantic join can be proven
 * by plain JVM tests against real compiler artifacts (no IDE fixture needed).
 */
internal object IgniterModelParser {

    /** Builds the model for [igapp]; returns [IgniterModel.EMPTY] if no artifacts are present. */
    fun parse(igapp: File): IgniterModel {
        val sourceMapFile = File(igapp, "sourcemap.json").takeIf { it.exists() }
        val semanticIrFile = File(igapp, "semantic_ir_program.json").takeIf { it.exists() }
        if (sourceMapFile == null && semanticIrFile == null) return IgniterModel.EMPTY

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
                            type = parseType(node.objectOrNull("type")),
                            deps = node.arrayOrNull("deps")?.mapNotNull { it.asString } ?: emptyList()
                        )
                    }
                }
            }
        }

        val symbols = ArrayList<SymbolNode>()
        val seen = HashSet<String>()

        sourceMapFile?.let src@{ f ->
            val root = parseObject(f) ?: return@src
            module = module ?: root.stringOrNull("module")
            root.arrayOrNull("nodes")?.forEach { n ->
                val node = n.asJsonObject
                val id = node.stringOrNull("node_id") ?: return@forEach
                val span = node.objectOrNull("source_span")
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

        // IR nodes the sourcemap didn't carry (no position).
        irByNode.forEach { (id, ir) ->
            if (id in seen) return@forEach
            symbols += symbol(id, null, ir.name, ir.type, 0, 0, null, ir.deps)
        }

        return IgniterModel(module, symbols, igapp, semanticIrFile, sourceMapFile)
    }

    /** Derives kind/contract/name from a node_id like `compute:Add.sum`, enriched by IR. */
    fun symbol(
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
        val params = obj.arrayOrNull("params")?.mapNotNull { parseType(it.asJsonObject) } ?: emptyList()
        return IgniterType(name, params)
    }

    private fun parseObject(f: File): JsonObject? = try {
        JsonParser.parseString(f.readText()).takeIf { it.isJsonObject }?.asJsonObject
    } catch (e: Exception) {
        null
    }
}

// --- small null-tolerant Gson accessors (file-private) ---

private fun JsonObject.stringOrNull(key: String) =
    get(key)?.takeIf { it.isJsonPrimitive }?.asString

private fun JsonObject.intOrNull(key: String) =
    get(key)?.takeIf { it.isJsonPrimitive }?.asInt

private fun JsonObject.arrayOrNull(key: String): JsonArray? =
    get(key)?.takeIf { it.isJsonArray }?.asJsonArray

private fun JsonObject.objectOrNull(key: String): JsonObject? =
    get(key)?.takeIf { it.isJsonObject }?.asJsonObject
