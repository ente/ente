package io.ente.ensu.settings

data class DeveloperSettingsState(
    val isAdvancedUnlocked: Boolean = false,
    val systemPrompt: String = ""
)
