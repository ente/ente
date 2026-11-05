package io.ente.ensu.chat

import io.ente.ensu.bindings.DbException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationNavigationTest {
    @Test(timeout = 10000)
    fun coldNotificationLoadsItsConversationAndOlderBranchAfterBootstrap() = runBlocking {
        for (cached in listOf(false, true)) {
            val repository = DelayedRepository()
            val finishBootstrap = CompletableDeferred<Unit>()
            val bootstrap = launch(start = CoroutineStart.UNDISPATCHED) { finishBootstrap.await() }
            var generationReset = false
            val navigation =
                async(start = CoroutineStart.UNDISPATCHED) {
                    loadNotificationConversation(
                        bootstrap,
                        "conversation",
                        "older-answer",
                        { if (cached) repository.sessions else emptyList() },
                        repository::listSessions,
                        repository::getMessages,
                    ) {
                        generationReset = true
                    }
                }
            try {
                assertTrue(repository.calls.isEmpty())
                assertFalse(generationReset)
                finishBootstrap.complete(Unit)
                repository.messagesEntered.await()
                assertEquals(
                    if (cached) listOf("messages:conversation")
                    else listOf("sessions", "messages:conversation"),
                    repository.calls,
                )
                assertFalse(generationReset)
                assertFalse(navigation.isCompleted)
                repository.releaseMessages.countDown()

                val conversation = checkNotNull(navigation.await())
                assertTrue(generationReset)
                assertEquals(repository.sessions, conversation.sessions)
                assertEquals(repository.messages, conversation.messages)
                assertEquals(
                    mapOf(
                        "question" to "older-answer",
                        "earlier-answer" to "question",
                        "root" to "earlier-answer",
                        "__root__" to "root",
                    ),
                    conversation.branchSelections,
                )
            } finally {
                finishBootstrap.complete(Unit)
                repository.releaseMessages.countDown()
                navigation.cancelAndJoin()
                bootstrap.cancelAndJoin()
            }
        }
    }

    @Test(timeout = 10000)
    fun newerNavigationCancelsNotificationDuringReadinessOrBootstrap() = runBlocking {
        for (ready in listOf(false, true)) {
            val repository = DelayedRepository()
            val readiness = CompletableDeferred<Unit>()
            if (ready) readiness.complete(Unit)
            val bootstrap = Job()
            val owner = NotificationNavigation { throw it }
            var generationReset = false
            val navigation =
                launch(start = CoroutineStart.UNDISPATCHED) {
                    owner.open {
                        readiness.await()
                        loadNotificationConversation(
                            bootstrap,
                            "conversation",
                            "older-answer",
                            { emptyList() },
                            repository::listSessions,
                            repository::getMessages,
                        ) {
                            generationReset = true
                        } != null
                    }
                }
            owner.cancel()
            readiness.complete(Unit)
            bootstrap.complete()
            navigation.join()
            assertTrue(navigation.isCancelled)
            assertTrue(repository.calls.isEmpty())
            assertFalse(generationReset)
            assertNull(owner.opened.value)
        }
    }

    @Test(timeout = 10000)
    fun newerNavigationWinsWhileNotificationReadIsPending() = runBlocking {
        for (openAnotherNotification in listOf(false, true)) {
            val repository = DelayedRepository()
            val owner = NotificationNavigation { throw it }
            owner.open { true }
            val priorToken = checkNotNull(owner.opened.value)
            var selectedAnswer = "earlier-answer"
            var generationReset = false
            val navigation =
                launch(start = CoroutineStart.UNDISPATCHED) {
                    owner.open {
                        val conversation =
                            loadNotificationConversation(
                                null,
                                "conversation",
                                "older-answer",
                                { repository.sessions },
                                repository::listSessions,
                                repository::getMessages,
                            ) {
                                generationReset = true
                            } ?: return@open false
                        selectedAnswer = conversation.branchSelections.getValue("question")
                        true
                    }
                }
            try {
                assertNull(owner.opened.value)
                repository.messagesEntered.await()
                assertEquals("earlier-answer", selectedAnswer)
                if (openAnotherNotification) {
                    owner.open {
                        selectedAnswer = "newer-answer"
                        true
                    }
                } else {
                    owner.cancel()
                    selectedAnswer = "newer-answer"
                }
                val latestToken = owner.opened.value
                assertEquals(openAnotherNotification, latestToken != null)
                repository.releaseMessages.countDown()
                navigation.join()
                assertTrue(navigation.isCancelled)
                assertFalse(generationReset)
                assertEquals("newer-answer", selectedAnswer)
                owner.acknowledge(priorToken)
                assertEquals(latestToken, owner.opened.value)
                owner.cancel()
                assertNull(owner.opened.value)
            } finally {
                repository.releaseMessages.countDown()
                navigation.cancelAndJoin()
            }
        }
    }

    @Test(timeout = 10000)
    fun unavailableConversationKeepsSelectionAndAllowsAnotherNotification() = runBlocking {
        for (unavailable in listOf("missing", "sessions", "messages")) {
            val repository = DelayedRepository()
            val error = DbException.Other("Database read failed")
            val failures = mutableListOf<DbException>()
            val owner = NotificationNavigation { failures.add(it) }
            var selectedAnswer = "earlier-answer"
            var generationReset = false
            owner.open { true }
            owner.open {
                val conversation =
                    loadNotificationConversation(
                        null,
                        if (unavailable == "missing") "deleted" else "conversation",
                        "older-answer",
                        { emptyList() },
                        {
                            if (unavailable == "sessions") throw error
                            repository.listSessions()
                        },
                        { throw error },
                    ) {
                        generationReset = true
                    } ?: return@open false
                selectedAnswer = conversation.branchSelections.getValue("question")
                true
            }
            assertEquals(if (unavailable == "missing") emptyList() else listOf(error), failures)
            assertFalse(generationReset)
            assertEquals(
                if (unavailable == "sessions") emptyList() else listOf("sessions"),
                repository.calls,
            )
            assertEquals("earlier-answer", selectedAnswer)
            assertNull(owner.opened.value)

            owner.open { true }
            assertNotNull(owner.opened.value)
        }
    }

    private class DelayedRepository {
        val sessions =
            listOf(
                ChatSession(id = "other", title = "Other conversation", updatedAtMillis = 1),
                ChatSession(
                    id = "conversation",
                    title = "Requested conversation",
                    updatedAtMillis = 0,
                ),
            )
        val messages =
            listOf(
                message("root"),
                message("earlier-answer", "root", MessageAuthor.Assistant),
                message("question", "earlier-answer"),
                message("older-answer", "question", MessageAuthor.Assistant),
                message("newer-answer", "question", MessageAuthor.Assistant),
            )
        val calls = mutableListOf<String>()
        val messagesEntered = CompletableDeferred<Unit>()
        val releaseMessages = CountDownLatch(1)

        fun listSessions(): List<ChatSession> {
            calls.add("sessions")
            return sessions
        }

        fun getMessages(sessionId: String): List<ChatMessage> {
            calls.add("messages:$sessionId")
            messagesEntered.complete(Unit)
            check(releaseMessages.await(5, TimeUnit.SECONDS))
            return messages
        }

        private fun message(
            id: String,
            parentId: String? = null,
            author: MessageAuthor = MessageAuthor.User,
        ) =
            ChatMessage(
                id = id,
                sessionId = "conversation",
                parentId = parentId,
                author = author,
                text = id,
                timestampMillis = 0,
            )
    }
}
