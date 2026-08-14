package io.ente.ensu.llm

data class ModelSettingsState(
    val modelId: String = "",
    val contextLength: String = "",
    val maxTokens: String = "",
    val temperature: String = "",
    val isSaving: Boolean = false
)
