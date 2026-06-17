package com.igniter.plugin.compiler

/**
 * Pure (IntelliJ-free) parser for the compiler's `compilation_report.json` and a
 * stdout fallback. Extracted from [IgniterCompilerService] so diagnostic parsing
 * can be proven by plain JVM tests against real reports.
 *
 * Canon diagnostic shape (verified live against `igniter_compiler`):
 * ```
 * { "rule": "OOF-TY0", "severity": "error", "message": "...",
 *   "line": 5            // Rust parse errors: top-level line, no col
 *   | "span": {"line","col"} | null   // Ruby igc / typecheck form
 * }
 * ```
 */
internal object IgniterReportParser {

    // OOF rule ids surfaced as warnings unless the report already marks them so.
    private val WARNING_CODES = setOf("OOF-L3", "OOF-M2", "OOF-P2")

    fun parseReport(json: String): List<OofDiagnostic> {
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
     * Last-resort scan of stdout when no report file was produced. The compiler
     * prints a `compiler_result` envelope to stdout; we look for rule ids with a
     * line hint.
     */
    fun parseFallbackOutput(raw: String): List<OofDiagnostic> {
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
}
