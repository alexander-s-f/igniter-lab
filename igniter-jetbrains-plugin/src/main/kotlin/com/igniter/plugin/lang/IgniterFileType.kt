package com.igniter.plugin.lang

import com.intellij.openapi.fileTypes.LanguageFileType
import com.intellij.openapi.util.IconLoader
import javax.swing.Icon

object IgniterFileType : LanguageFileType(IgniterLanguage) {
    val ICON: Icon by lazy {
        IconLoader.getIcon("/icons/igniter_file.svg", IgniterFileType::class.java)
    }

    override fun getName(): String = "Igniter Contract"
    override fun getDescription(): String = "Igniter contract source file"
    override fun getDefaultExtension(): String = "ig"
    override fun getIcon(): Icon = ICON
}
