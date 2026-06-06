package com.igniter.plugin.settings

import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.components.PersistentStateComponent
import com.intellij.openapi.components.Service
import com.intellij.openapi.components.State
import com.intellij.openapi.components.Storage
import com.intellij.util.xmlb.XmlSerializerUtil

@State(
    name = "IgniterSettings",
    storages = [Storage("igniter-plugin.xml")]
)
@Service(Service.Level.APP)
class IgniterSettings : PersistentStateComponent<IgniterSettings> {

    // The path to the igniter_compiler binary.
    // Empty string means "find on PATH".
    var compilerPath: String = ""

    // When true the ExternalAnnotator compiles the file on each change.
    var autoCompileOnSave: Boolean = true

    // Show "EMIT_OBS" observations in the tool window.
    var showObservations: Boolean = true

    override fun getState(): IgniterSettings = this

    override fun loadState(state: IgniterSettings) {
        XmlSerializerUtil.copyBean(state, this)
    }

    companion object {
        @JvmStatic
        fun getInstance(): IgniterSettings =
            ApplicationManager.getApplication().getService(IgniterSettings::class.java)
    }
}
