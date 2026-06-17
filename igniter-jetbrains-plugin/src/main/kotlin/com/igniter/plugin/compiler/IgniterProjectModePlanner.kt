package com.igniter.plugin.compiler

/**
 * Project-mode compile planning for the JetBrains plugin.
 * Card LAB-JETBRAINS-PROJECT-MODE-DELEGATION-P7 (supersedes the P6
 * plugin-side import graph scanner `IgniterImportCompilePlanner`).
 *
 * The native `igniter_compiler` now owns project assembly (cards
 * LAB-COMPILER-PROJECT-MODE-COMPILE-P1 / LAB-COMPILER-PROJECT-OVERLAY-P2):
 *
 *   igniter_compiler compile \
 *     --project-root <root> \
 *     --entry <current-module> \
 *     --overlay <on-disk-current.ig>=<temp-editor-buffer.ig> \
 *     --out <out.igapp>
 *
 * The compiler scans the source roots, builds the module index, resolves the
 * transitive import closure for `--entry`, and reads the overlay buffer in place
 * of the on-disk current file (so unsaved editor text wins). The plugin no longer
 * scans the project or builds an import graph — it only supplies the project root,
 * the current module name, and the overlay buffer.
 *
 * This object holds the small amount of *pure* knowledge the plugin still needs:
 *  - read the current file's `module` name (the entry),
 *  - decide whether project mode applies (the file declares a module AND has at
 *    least one non-stdlib import),
 *  - build the exact CLI argv (so the invocation shape is unit-tested).
 *
 * `stdlib.*` imports are compiler-owned and never imply a project file.
 */
object IgniterProjectModePlanner {

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

    /**
     * Project mode applies when the file declares a module (the `--entry`) and has
     * at least one non-stdlib import to resolve from the project graph. Files with
     * no non-stdlib imports keep the unchanged single-file path (faster, and
     * project mode would add nothing). Returns the entry module when applicable.
     */
    fun entryModuleForProjectMode(text: String): String? {
        val module = moduleNameOf(text) ?: return null
        return if (importedModules(text).isNotEmpty()) module else null
    }

    /**
     * The exact `igniter_compiler` project-mode + overlay argv. [overlayOriginal]
     * is the on-disk path of the current file; [overlayBuffer] is the file holding
     * the (possibly unsaved) editor text the compiler should read for it.
     */
    fun buildCompileArgs(
        binary: String,
        projectRoot: String,
        entryModule: String,
        overlayOriginal: String,
        overlayBuffer: String,
        outIgapp: String,
    ): List<String> = listOf(
        binary,
        "compile",
        "--project-root", projectRoot,
        "--entry", entryModule,
        "--overlay", "$overlayOriginal=$overlayBuffer",
        "--out", outIgapp,
    )
}
