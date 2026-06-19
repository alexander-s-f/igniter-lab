package com.igniter.plugin.navigation

import com.igniter.plugin.index.IgniterSymbolIndex
import com.intellij.navigation.ChooseByNameContributor
import com.intellij.navigation.ItemPresentation
import com.intellij.navigation.NavigationItem
import com.intellij.openapi.fileEditor.OpenFileDescriptor
import com.intellij.openapi.project.Project
import com.intellij.openapi.vfs.VirtualFile
import com.intellij.psi.search.GlobalSearchScope
import com.intellij.util.indexing.FileBasedIndex
import javax.swing.Icon

/**
 * Project-wide "Go to Symbol" (Ctrl+Alt+Shift+N) over Igniter declarations.
 *
 * Backed by the persistent [IgniterSymbolIndex] (the cross-file layer must stay
 * index-based — a FileBasedIndex indexer cannot run the compiler). Names are the
 * qualified `kind:name` keys so every declaration is listed distinctly; the
 * presentation shows the bare name with its kind.
 */
class IgniterGotoSymbolContributor : ChooseByNameContributor {

    override fun getNames(project: Project, includeNonProjectItems: Boolean): Array<String> {
        val names = sortedSetOf<String>()
        val scope = scope(project, includeNonProjectItems)
        FileBasedIndex.getInstance().processAllKeys(IgniterSymbolIndex.NAME, { key ->
            if (key.contains(':')) names.add(key)   // qualified keys only
            true
        }, scope, null)
        return names.toTypedArray()
    }

    override fun getItemsByName(
        name: String,
        pattern: String,
        project: Project,
        includeNonProjectItems: Boolean
    ): Array<NavigationItem> {
        val index = FileBasedIndex.getInstance()
        val scope = scope(project, includeNonProjectItems)
        val kind = name.substringBefore(':')
        val bare = name.substringAfter(':')

        val items = ArrayList<NavigationItem>()
        for (vf in index.getContainingFiles(IgniterSymbolIndex.NAME, name, scope)) {
            val offsets = index.getValues(IgniterSymbolIndex.NAME, name, GlobalSearchScope.fileScope(project, vf))
            for (offset in offsets) {
                items += IgniterSymbolNavItem(project, vf, offset, bare, "$kind · ${vf.name}")
            }
        }
        return items.toTypedArray()
    }

    private fun scope(project: Project, includeNonProjectItems: Boolean): GlobalSearchScope =
        if (includeNonProjectItems) GlobalSearchScope.allScope(project)
        else GlobalSearchScope.projectScope(project)
}

/** A navigable symbol entry pointing at (file, offset). */
class IgniterSymbolNavItem(
    private val project: Project,
    private val vFile: VirtualFile,
    private val offset: Int,
    private val itemName: String,
    private val locationText: String
) : NavigationItem {

    override fun getName(): String = itemName

    override fun getPresentation(): ItemPresentation = object : ItemPresentation {
        override fun getPresentableText(): String = itemName
        override fun getLocationString(): String = locationText
        override fun getIcon(unused: Boolean): Icon? = null
    }

    override fun navigate(requestFocus: Boolean) {
        if (vFile.isValid) OpenFileDescriptor(project, vFile, offset).navigate(requestFocus)
    }

    override fun canNavigate(): Boolean = vFile.isValid
    override fun canNavigateToSource(): Boolean = vFile.isValid
}
