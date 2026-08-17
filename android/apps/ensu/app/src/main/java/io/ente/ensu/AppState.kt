package io.ente.ensu
import io.ente.ensu.llm.ModelSettingsState
import io.ente.ensu.settings.DeveloperSettingsState
import io.ente.ensu.chat.ChatState
import io.ente.ensu.knowledge.KnowledgeState

data class AppState(
    val chat: ChatState = ChatState(),
    val knowledge: KnowledgeState = KnowledgeState(),
    val developerSettings: DeveloperSettingsState = DeveloperSettingsState(),
    val modelSettings: ModelSettingsState = ModelSettingsState()
)
