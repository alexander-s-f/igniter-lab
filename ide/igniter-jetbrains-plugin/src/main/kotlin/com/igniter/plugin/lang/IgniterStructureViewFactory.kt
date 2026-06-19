package com.igniter.plugin.lang

import com.intellij.ide.structureView.StructureViewBuilder
import com.intellij.ide.structureView.StructureViewModel
import com.intellij.ide.structureView.StructureViewModelBase
import com.intellij.ide.structureView.StructureViewTreeElement
import com.intellij.ide.structureView.TreeBasedStructureViewBuilder
import com.intellij.ide.util.treeView.smartTree.SortableTreeElement
import com.intellij.ide.util.treeView.smartTree.TreeElement
import com.intellij.lang.PsiStructureViewFactory
import com.intellij.navigation.ItemPresentation
import com.intellij.openapi.editor.Editor
import com.intellij.openapi.util.IconLoader
import com.intellij.psi.PsiElement
import com.intellij.psi.PsiFile
import javax.swing.Icon

// ---------------------------------------------------------------------------
// Presentation helpers
// ---------------------------------------------------------------------------

private class SimplePresentation(
    private val text: String,
    private val icon: Icon?
) : ItemPresentation {
    override fun getPresentableText(): String = text
    override fun getLocationString(): String? = null
    override fun getIcon(unused: Boolean): Icon? = icon
}

// ---------------------------------------------------------------------------
// Leaf tree element (input / output / def / compute node)
// ---------------------------------------------------------------------------

private class IgniterLeafElement(
    private val psi: PsiElement,
    private val label: String,
    private val icon: Icon?
) : StructureViewTreeElement, SortableTreeElement {
    override fun getValue(): Any = psi
    override fun getAlphaSortKey(): String = label
    override fun getPresentation(): ItemPresentation = SimplePresentation(label, icon)
    override fun getChildren(): Array<TreeElement> = emptyArray()
    override fun navigate(requestFocus: Boolean) {
        if (psi is com.intellij.pom.Navigatable) (psi as com.intellij.pom.Navigatable).navigate(requestFocus)
    }
    override fun canNavigate(): Boolean = psi.isValid
    override fun canNavigateToSource(): Boolean = psi.isValid
}

// ---------------------------------------------------------------------------
// Contract / def block element
// ---------------------------------------------------------------------------

private class IgniterBlockElement(
    private val psi: PsiElement,
    private val label: String,
    private val icon: Icon?,
    private val children: List<TreeElement>
) : StructureViewTreeElement, SortableTreeElement {
    override fun getValue(): Any = psi
    override fun getAlphaSortKey(): String = label
    override fun getPresentation(): ItemPresentation = SimplePresentation(label, icon)
    override fun getChildren(): Array<TreeElement> = children.toTypedArray()
    override fun navigate(requestFocus: Boolean) {
        if (psi is com.intellij.pom.Navigatable) (psi as com.intellij.pom.Navigatable).navigate(requestFocus)
    }
    override fun canNavigate(): Boolean = psi.isValid
    override fun canNavigateToSource(): Boolean = psi.isValid
}

// ---------------------------------------------------------------------------
// Root element — parses PSI token stream for structure
// ---------------------------------------------------------------------------

private class IgniterFileStructureElement(private val file: IgniterFile) : StructureViewTreeElement {
    override fun getValue(): Any = file
    override fun getPresentation(): ItemPresentation = SimplePresentation(file.name, IgniterFileType.ICON)

    override fun navigate(requestFocus: Boolean) = file.navigate(requestFocus)
    override fun canNavigate(): Boolean = file.canNavigate()
    override fun canNavigateToSource(): Boolean = file.canNavigateToSource()

    override fun getChildren(): Array<TreeElement> {
        val elements = mutableListOf<TreeElement>()
        val text = file.text
        val lines = text.lines()
        var lineStart = 0

        // Regex-based structural scanning (no full parser yet)
        val contractRe = Regex("""^\s*contract\s+(\w+)""")
        val defRe      = Regex("""^\s*def\s+(\w+)""")
        val inputRe    = Regex("""^\s*input\s+(\w+)""")
        val outputRe   = Regex("""^\s*output\s+(\w+)""")
        val computeRe  = Regex("""^\s*compute\s+(\w+)""")

        data class BlockCtx(val name: String, val offset: Int, val kind: String)
        var currentBlock: BlockCtx? = null
        val blockChildren = mutableListOf<TreeElement>()

        for (line in lines) {
            val offset = lineStart
            val psi = file.findElementAt(offset)
            if (psi == null) { lineStart += line.length + 1; continue }

            contractRe.find(line)?.let { m ->
                // Flush previous block
                currentBlock?.let { b ->
                    val bPsi = file.findElementAt(b.offset) ?: psi
                    elements += IgniterBlockElement(bPsi, "${b.kind} ${b.name}", null, blockChildren.toList())
                    blockChildren.clear()
                }
                currentBlock = BlockCtx(m.groupValues[1], offset, "contract")
            }

            defRe.find(line)?.let { m ->
                currentBlock?.let { b ->
                    val bPsi = file.findElementAt(b.offset) ?: psi
                    elements += IgniterBlockElement(bPsi, "${b.kind} ${b.name}", null, blockChildren.toList())
                    blockChildren.clear()
                }
                currentBlock = BlockCtx(m.groupValues[1], offset, "def")
            }

            if (currentBlock != null) {
                inputRe.find(line)?.let { m ->
                    blockChildren += IgniterLeafElement(psi, "input ${m.groupValues[1]}", null)
                }
                outputRe.find(line)?.let { m ->
                    blockChildren += IgniterLeafElement(psi, "output ${m.groupValues[1]}", null)
                }
                computeRe.find(line)?.let { m ->
                    blockChildren += IgniterLeafElement(psi, "compute ${m.groupValues[1]}", null)
                }
            }

            lineStart += line.length + 1
        }

        // Flush last block
        currentBlock?.let { b ->
            val bPsi = file.findElementAt(b.offset) ?: file
            elements += IgniterBlockElement(bPsi, "${b.kind} ${b.name}", null, blockChildren.toList())
        }

        return elements.toTypedArray()
    }
}

// ---------------------------------------------------------------------------
// StructureViewModel
// ---------------------------------------------------------------------------

private class IgniterStructureViewModel(editor: Editor?, file: IgniterFile) :
    StructureViewModelBase(file, editor, IgniterFileStructureElement(file)) {

    override fun getSuitableClasses(): Array<Class<*>> = arrayOf(IgniterFile::class.java)
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

class IgniterStructureViewFactory : PsiStructureViewFactory {
    override fun getStructureViewBuilder(psiFile: PsiFile): StructureViewBuilder? {
        val igniterFile = psiFile as? IgniterFile ?: return null
        return object : TreeBasedStructureViewBuilder() {
            override fun createStructureViewModel(editor: Editor?): StructureViewModel =
                IgniterStructureViewModel(editor, igniterFile)
        }
    }
}
