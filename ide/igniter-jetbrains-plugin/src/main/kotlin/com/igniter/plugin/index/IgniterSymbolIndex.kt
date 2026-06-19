package com.igniter.plugin.index

import com.igniter.plugin.lang.IgniterFileType
import com.intellij.util.indexing.*
import com.intellij.util.io.DataExternalizer
import com.intellij.util.io.EnumeratorStringDescriptor
import com.intellij.util.io.KeyDescriptor
import java.io.DataInput
import java.io.DataOutput

class IgniterSymbolIndex : FileBasedIndexExtension<String, Int>() {

    companion object {
        @JvmField
        val NAME: ID<String, Int> = ID.create("igniter.symbols")

        // Regex patterns for top-level declarations
        private val PATTERNS = listOf(
            Regex("""^\s*contract\s+(\w+)""") to "contract",
            Regex("""^\s*def\s+(\w+)""")      to "def",
            Regex("""^\s*compute\s+(\w+)""")  to "compute",
            Regex("""^\s*input\s+(\w+)""")    to "input",
            Regex("""^\s*output\s+(\w+)""")   to "output",
            Regex("""^\s*loop\s+(\w+)""")     to "loop",
        )
    }

    override fun getName(): ID<String, Int> = NAME
    override fun getVersion(): Int = 2
    override fun dependsOnFileContent(): Boolean = true
    override fun getInputFilter(): FileBasedIndex.InputFilter =
        DefaultFileTypeSpecificInputFilter(IgniterFileType)

    override fun getIndexer(): DataIndexer<String, Int, FileContent> =
        DataIndexer { fileContent ->
            val result = HashMap<String, Int>()
            val text = fileContent.contentAsText.toString()
            var offset = 0
            for (line in text.split('\n')) {
                for ((re, kind) in PATTERNS) {
                    re.find(line)?.let { m ->
                        val name = m.groupValues[1]
                        // offset of the name token within the file
                        val nameOffset = offset + line.indexOf(name, m.range.first)
                        result["$kind:$name"] = nameOffset
                        // also index by bare name for cross-kind lookup
                        result[name] = nameOffset
                    }
                }
                offset += line.length + 1
            }
            result
        }

    override fun getKeyDescriptor(): KeyDescriptor<String> = EnumeratorStringDescriptor.INSTANCE

    override fun getValueExternalizer(): DataExternalizer<Int> = object : DataExternalizer<Int> {
        override fun save(out: DataOutput, value: Int) = out.writeInt(value)
        override fun read(inp: DataInput): Int = inp.readInt()
    }
}
