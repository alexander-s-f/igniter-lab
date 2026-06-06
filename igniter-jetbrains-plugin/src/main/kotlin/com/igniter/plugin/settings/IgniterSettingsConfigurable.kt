package com.igniter.plugin.settings

import com.intellij.openapi.options.Configurable
import com.intellij.openapi.ui.TextFieldWithBrowseButton
import com.intellij.ui.components.JBCheckBox
import com.intellij.ui.components.JBLabel
import com.intellij.util.ui.FormBuilder
import javax.swing.JComponent
import javax.swing.JPanel

class IgniterSettingsConfigurable : Configurable {

    private var panel: JPanel? = null
    private val compilerPathField  = TextFieldWithBrowseButton()
    private val autoCompileCheckBox   = JBCheckBox("Auto-compile on save")
    private val showObservationsCheckBox = JBCheckBox("Show observations in tool window")

    override fun getDisplayName(): String = "Igniter"

    override fun createComponent(): JComponent {
        compilerPathField.addBrowseFolderListener(
            "Select igniter_compiler Binary",
            "Choose the path to the igniter_compiler executable",
            null,
            com.intellij.openapi.fileChooser.FileChooserDescriptorFactory.createSingleFileDescriptor()
        )

        panel = FormBuilder.createFormBuilder()
            .addLabeledComponent(JBLabel("Compiler path (leave empty to use PATH):"), compilerPathField, 1, false)
            .addComponent(autoCompileCheckBox, 1)
            .addComponent(showObservationsCheckBox, 1)
            .addComponentFillVertically(JPanel(), 0)
            .panel

        return panel!!
    }

    override fun isModified(): Boolean {
        val settings = IgniterSettings.getInstance()
        return compilerPathField.text.trim() != settings.compilerPath
            || autoCompileCheckBox.isSelected    != settings.autoCompileOnSave
            || showObservationsCheckBox.isSelected != settings.showObservations
    }

    override fun apply() {
        val settings = IgniterSettings.getInstance()
        settings.compilerPath      = compilerPathField.text.trim()
        settings.autoCompileOnSave = autoCompileCheckBox.isSelected
        settings.showObservations  = showObservationsCheckBox.isSelected
    }

    override fun reset() {
        val settings = IgniterSettings.getInstance()
        compilerPathField.text            = settings.compilerPath
        autoCompileCheckBox.isSelected    = settings.autoCompileOnSave
        showObservationsCheckBox.isSelected = settings.showObservations
    }

    override fun disposeUIResources() {
        panel = null
    }
}
