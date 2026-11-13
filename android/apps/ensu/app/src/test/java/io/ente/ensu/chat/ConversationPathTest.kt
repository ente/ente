package io.ente.ensu.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class ConversationPathTest {
    @Test
    fun followsTheRequestedBranchThroughDuplicateEdits() {
        val root = message("root")
        val editedRoot = root.copy(id = "edited-root", timestampMillis = 1)
        val answer = message("answer", editedRoot.id, MessageAuthor.Assistant)
        val user = message("user", answer.id)
        val editedUser = user.copy(id = "edited-user", timestampMillis = 1)
        val descendant = message("descendant", editedUser.id, MessageAuthor.Assistant)
        val messages = listOf(root, editedRoot, answer, user, editedUser, descendant)

        assertEquals(listOf(editedRoot.id), conversationPath(messages, editedRoot))
        assertEquals(
            listOf(editedRoot.id, answer.id, editedUser.id),
            conversationPath(messages, editedUser),
        )
    }

    @Test
    fun stopsAtAMissingParentWithoutChangingMessageIds() {
        val root = message("orphan", "deleted-parent")
        val target = message("target", root.id)

        assertEquals(listOf(root.id, target.id), conversationPath(listOf(root, target), target))
    }

    @Test
    fun terminatesWhenParentLinksCycle() {
        val first = message("first", "second")
        val second = message("second", first.id)

        assertEquals(listOf(first.id, second.id), conversationPath(listOf(first, second), second))
    }

    private fun message(
        id: String,
        parentId: String? = null,
        author: MessageAuthor = MessageAuthor.User,
    ) =
        ChatMessage(
            id = id,
            sessionId = "session",
            parentId = parentId,
            author = author,
            text = "Same text",
            timestampMillis = 0,
        )
}
