package io.ente.ensu.llm

import io.ente.ensu.bindings.ModelDownloadTarget

data class LlmModelTarget(
    val id: String,
    val url: String,
    val mmprojUrl: String? = null,
    val contextLength: Int? = null,
    val maxTokens: Int? = null
) {
    val downloadTarget: ModelDownloadTarget
        get() = ModelDownloadTarget.Gguf(id = id, url = url, mmprojUrl = mmprojUrl)
}

data class DownloadProgress(
    val percent: Int?,
    val status: String,
    val phase: DownloadPhase = DownloadPhase.Downloading
)

enum class DownloadPhase {
    Downloading,
    Loading,
    Ready,
    Failed
}

enum class LlmMessageRole {
    User,
    Assistant,
    System
}

data class LlmMessage(
    val text: String,
    val role: LlmMessageRole,
    val hasAttachments: Boolean = false
)

data class GenerationSummary(
    val jobId: Long,
    val generatedTokens: Int,
    val totalTimeMs: Long?
)
