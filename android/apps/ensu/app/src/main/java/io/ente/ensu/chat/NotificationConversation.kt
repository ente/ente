package io.ente.ensu.chat

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.withContext

internal data class NotificationConversation(
    val sessions: List<ChatSession>,
    val messages: List<ChatMessage>,
    val branchSelections: Map<String, String>,
)

internal suspend fun loadNotificationConversation(
    initialSessionLoad: Job?,
    sessionId: String,
    messageId: String?,
    cachedSessions: () -> List<ChatSession>,
    listSessions: () -> List<ChatSession>,
    getMessages: (String) -> List<ChatMessage>,
    onSessionFound: () -> Unit,
): NotificationConversation? {
    initialSessionLoad?.join()
    val cached = cachedSessions()
    val sessions =
        if (cached.any { it.id == sessionId }) cached
        else withContext(Dispatchers.IO) { listSessions() }
    if (sessions.none { it.id == sessionId }) return null
    onSessionFound()
    val messages = withContext(Dispatchers.IO) { getMessages(sessionId) }
    val byId = messages.associateBy { it.id }
    val selections = mutableMapOf<String, String>()
    val visited = mutableSetOf<String>()
    var node = messageId?.let(byId::get)
    while (node != null && visited.add(node.id)) {
        selections[node.parentId ?: "__root__"] = node.id
        node = node.parentId?.let(byId::get)
    }
    return NotificationConversation(sessions, messages, selections)
}
