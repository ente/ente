package io.ente.ensu.chat

import io.ente.ensu.device.ChatDeviceCapability
import io.ente.ensu.llm.DownloadPhase

data class ChatState(
    val sessions: List<ChatSession> = emptyList(),
    val currentSessionId: String? = null,
    val sourceSelectionReady: Boolean = false,
    val sourceSelectionError: String? = null,
    val messages: List<ChatMessage> = emptyList(),
    val streamingResponse: String = "",
    val streamingParentId: String? = null,
    val isGenerating: Boolean = false,
    val preparationStatus: String? = null,
    val isDownloading: Boolean = false,
    val downloadPercent: Int? = null,
    val downloadStatus: String? = null,
    val downloadPhase: DownloadPhase? = null,
    val messageText: String = "",
    val attachments: List<Attachment> = emptyList(),
    val editingMessageId: String? = null,
    val branchSelections: Map<String, Int> = emptyMap(),
    val isProcessingAttachments: Boolean = false,
    val transientAssistantError: String? = null,
    val transientAssistantParentId: String? = null,
    val isModelDownloaded: Boolean = false,
    val isModelStateKnown: Boolean = false,
    val supportsImageAttachments: Boolean = false,
    val modelDownloadSizeBytes: Long? = null,
    val hasRequestedModelDownload: Boolean = false,
    val deviceCapability: ChatDeviceCapability = ChatDeviceCapability.Unknown,
    val showUnsupportedDeviceDialog: Boolean = false,
    val overflowDialog: OverflowDialogState? = null,
)

data class OverflowDialogState(
    val inputTokens: Int,
    val inputBudget: Int,
    val contextLength: Int,
    val maxOutput: Int,
)
