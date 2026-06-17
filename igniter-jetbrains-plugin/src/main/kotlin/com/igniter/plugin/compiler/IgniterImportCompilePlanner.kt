package com.igniter.plugin.compiler

import java.nio.file.Files
import java.nio.file.Path

/**
 * Import-aware compilation planning for the JetBrains plugin.
 * Card LAB-JETBRAINS-IMPORT-AWARE-COMPILE-P6.
 *
 * The native `igniter_compiler` only validates and resolves imports when it is
 * given *all* the source files of a program on one command line
 * (`compile A.ig B.ig … --out OUT`); it does not scan the filesystem. When the
 * editor compiles only the current temp file, an importing `.ig` loses its
 * imported type/contract declarations and the typechecker emits false
 * `OOF-P1 Unresolved field: …` diagnostics. (Verified live: single source →
 * `OOF-P1`; current + imported module → clean; a genuinely missing import in
 * multi-file mode → compiler-authoritative `OOF-IMP2`.)
 *
 * This object is split into:
 *  - **pure** text parsing + import-graph resolution ([moduleNameOf],
 *    [importedModules], [isStdlib], [resolve]) — no IntelliJ, no I/O, unit-tested;
 *  - a thin filesystem [scanProject] that builds the `module path -> file` index.
 *
 * `stdlib.*` imports are owned by the compiler and never resolved to a project
 * file. Unresolved non-stdlib modules are left for the compiler to report
 * (`OOF-IMP*`) rather than guessed at here.
 */
object IgniterImportCompilePlanner {

    private val MODULE_RE = Regex("""^\s*module\s+([A-Za-z_][\w.]*)""")
    private val IMPORT_RE = Regex("""^\s*import\s+([A-Za-z_][\w.]*)""")

    /** Module path declared by the first top-level `module X` line, or null. */
    fun moduleNameOf(text: String): String? =
        text.lineSequence().firstNotNullOfOrNull { MODULE_RE.find(it)?.groupValues?.get(1) }

    /**
     * Non-stdlib module paths imported by [text], in first-seen order, de-duplicated.
     * Handles both `import Foo.Bar` and selective `import Foo.Bar.{ Name }`
     * (the module path is the part before `.{`).
     */
    fun importedModules(text: String): List<String> =
        text.lineSequence()
            .mapNotNull { IMPORT_RE.find(it)?.groupValues?.get(1)?.trimEnd('.') }
            .filter { it.isNotEmpty() && !isStdlib(it) }
            .distinct()
            .toList()

    /** True for the compiler-owned `stdlib` namespace (no project file needed). */
    fun isStdlib(modulePath: String): Boolean =
        modulePath == "stdlib" || modulePath.startsWith("stdlib.")

    /** A project module: the file that declares [modulePath] and the modules it imports. */
    data class ModuleEntry(val modulePath: String, val filePath: String, val imports: List<String>)

    /**
     * Transitive closure of [currentImports] resolved against [index]
     * (`module path -> entry`). [currentModule] is excluded so the current file's
     * on-disk copy is never passed alongside its in-editor temp copy (which would
     * be a duplicate-module error). Returns the file paths to compile *with* the
     * current source, in deterministic (sorted) order. Modules absent from the
     * index are silently skipped — the compiler is the authority on missing imports.
     */
    fun resolve(
        currentModule: String?,
        currentImports: List<String>,
        index: Map<String, ModuleEntry>
    ): List<String> {
        val visited = HashSet<String>()
        currentModule?.let { visited.add(it) }
        val files = LinkedHashSet<String>()
        val queue = ArrayDeque(currentImports.filterNot { isStdlib(it) })
        while (queue.isNotEmpty()) {
            val mod = queue.removeFirst()
            if (!visited.add(mod)) continue
            val entry = index[mod] ?: continue
            files.add(entry.filePath)
            entry.imports.filterNot { isStdlib(it) || it in visited }.forEach { queue.add(it) }
        }
        return files.sorted()
    }

    // -----------------------------------------------------------------------
    // Filesystem index (thin I/O; the graph logic above stays pure)
    // -----------------------------------------------------------------------

    /** Directories never worth walking for `.ig` modules. */
    private val SKIP_DIRS = setOf(
        ".git", ".idea", ".gradle", "build", "target", "out", "dist", "node_modules"
    )
    private const val MAX_FILES = 5000

    /**
     * Walks [root] for `.ig` files (skipping build/VCS dirs) and builds a
     * `module path -> ModuleEntry` index. [excludePath] (the current file's
     * on-disk path) is skipped so its in-editor text is the single source of
     * truth for that module. On a duplicate module path, the first file wins.
     */
    fun scanProject(root: Path, excludePath: String? = null): Map<String, ModuleEntry> {
        if (!Files.isDirectory(root)) return emptyMap()
        val index = LinkedHashMap<String, ModuleEntry>()
        var count = 0
        Files.walk(root).use { stream ->
            for (path in stream) {
                if (count >= MAX_FILES) break
                if (!Files.isRegularFile(path)) continue
                if (path.fileName?.toString()?.endsWith(".ig") != true) continue
                if (root.relativize(path).any { it.toString() in SKIP_DIRS }) continue
                val abs = path.toAbsolutePath().toString()
                if (excludePath != null && abs == excludePath) continue
                count++
                val text = runCatching { Files.readString(path) }.getOrNull() ?: continue
                val module = moduleNameOf(text) ?: continue
                index.putIfAbsent(module, ModuleEntry(module, abs, importedModules(text)))
            }
        }
        return index
    }
}
