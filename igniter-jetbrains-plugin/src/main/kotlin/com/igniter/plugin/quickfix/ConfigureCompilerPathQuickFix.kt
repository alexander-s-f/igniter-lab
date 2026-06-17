package com.igniter.plugin.quickfix

import com.igniter.plugin.settings.IgniterSettingsConfigurable
import com.intellij.codeInsight.intention.IntentionAction
import com.intellij.codeInsight.intention.preview.IntentionPreviewInfo
import com.intellij.openapi.editor.Editor
import com.intellij.openapi.options.ShowSettingsUtil
import com.intellij.openapi.project.Project
import com.intellij.psi.PsiFile

/**
 * Quickfix for `PLUGIN-001` (igniter_compiler not found): opens the Igniter
 * settings configurable so the developer can set the compiler path.
 *
 * Strictly non-destructive — opens a dialog, never edits `.ig` source (hence
 * [startInWriteAction] = false and an empty intention preview).
 */
class ConfigureCompilerPathQuickFix : IntentionAction {

    override fun getText(): String = IgniterQuickFix.CONFIGURE_COMPILER_PATH.displayText

    override fun getFamilyName(): String = "Igniter"

    override fun isAvailable(project: Project, editor: Editor?, file: PsiFile?): Boolean = true

    override fun startInWriteAction(): Boolean = false

    override fun invoke(project: Project, editor: Editor?, file: PsiFile?) {
        ShowSettingsUtil.getInstance().showSettingsDialog(project, IgniterSettingsConfigurable::class.java)
    }

    // Opening a settings dialog has no source-level preview.
    override fun generatePreview(project: Project, editor: Editor, file: PsiFile): IntentionPreviewInfo =
        IntentionPreviewInfo.EMPTY
}
