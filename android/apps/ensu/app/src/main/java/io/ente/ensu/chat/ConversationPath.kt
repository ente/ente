package io.ente.ensu.chat

internal fun conversationPath(messages: List<ChatMessage>, target: ChatMessage): List<String> {
    val byId = messages.associateBy { it.id }
    val path = mutableListOf<String>()
    val visited = mutableSetOf<String>()
    var current: ChatMessage? = target
    while (current != null && visited.add(current.id)) {
        path.add(current.id)
        current = current.parentId?.let(byId::get)
    }
    return path.asReversed()
}
