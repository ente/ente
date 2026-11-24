package io.ente.ensu.chat

import android.content.Context
import io.ente.ensu.bindings.ConversationPreparation
import io.ente.ensu.bindings.ConversationRequest
import io.ente.ensu.bindings.DbAttachmentKind
import io.ente.ensu.bindings.DbAttachmentMeta
import io.ente.ensu.bindings.DbException
import io.ente.ensu.bindings.DbMessage
import io.ente.ensu.bindings.DbSender
import io.ente.ensu.bindings.EnsuDb
import io.ente.ensu.bindings.LlmContext
import io.ente.ensu.bindings.TodoItem
import io.ente.ensu.bindings.ToolTurnStatus
import io.ente.ensu.bindings.ToolsObserver
import io.ente.ensu.bindings.cleanAssistantText
import io.ente.ensu.storage.CredentialStore
import io.ente.ensu.storage.FilePathManager
import java.io.File

internal data class TodoTurn(val reply: ChatMessage, val status: ToolTurnStatus)

class ChatRepository(
    context: Context,
    credentialStore: CredentialStore,
) {

    private val filePaths = FilePathManager(context)
    private val attachmentsDir = filePaths.attachmentsDir
    private val dbFile = filePaths.mainDbFile
    private val dbKey = credentialStore.getOrCreateChatDbKey(filePaths.hasChatData)
    @Volatile var onToolsChanged: () -> Unit = {}
    private var db: EnsuDb = openDb(dbFile, dbKey)

    init {
        pruneOrphanedAttachments()
    }

    fun listSessions(): List<ChatSession> = withDbRecovery {
        val sessions = db.listSessions()
        sessions.map { session ->
            val messages = runCatching { db.getMessages(session.uuid) }.getOrNull().orEmpty()
            val firstMessage =
                messages
                    .firstOrNull()
                    ?.let { message ->
                        if (message.sender == DbSender.OTHER) cleanAssistantText(message.text)
                        else message.text
                    }
                    .orEmpty()
            val lastMessage =
                messages.lastOrNull()?.let { message ->
                    if (message.sender == DbSender.OTHER) cleanAssistantText(message.text)
                    else message.text
                }
            val isPlaceholder =
                session.title.isBlank() || session.title.equals("New Chat", ignoreCase = true)
            val seedTitle = if (isPlaceholder) firstMessage else session.title
            ChatSession(
                id = session.uuid,
                title = sessionTitleFromText(seedTitle, fallback = session.title),
                lastMessagePreview = lastMessage,
                updatedAtMillis = session.updatedAtUs / 1000,
            )
        }
    }

    fun createSession(title: String): ChatSession = withDbRecovery {
        val session = db.createSession(title)
        ChatSession(
            id = session.uuid,
            title = session.title,
            lastMessagePreview = null,
            updatedAtMillis = session.updatedAtUs / 1000,
        )
    }

    fun deleteSession(sessionId: String) = withDbRecovery {
        db.deleteSession(sessionId).forEach { id -> File(attachmentsDir, id).delete() }
    }

    fun getMessages(sessionId: String): List<ChatMessage> = withDbRecovery {
        db.getMessages(sessionId).map { message ->
            toMessage(
                message,
                attachments =
                    message.attachments.map { meta ->
                        val file = File(attachmentsDir, meta.id)
                        Attachment(
                            id = meta.id,
                            name = meta.name,
                            sizeBytes = meta.size,
                            type =
                                when (meta.kind) {
                                    DbAttachmentKind.IMAGE -> AttachmentType.Image
                                    DbAttachmentKind.DOCUMENT -> AttachmentType.Document
                                },
                            localPath = file.takeIf { it.exists() }?.absolutePath,
                            isUploading = false,
                        )
                    },
            )
        }
    }

    fun insertMessage(
        sessionId: String,
        parentId: String?,
        author: MessageAuthor,
        text: String,
        attachments: List<Attachment>,
    ): ChatMessage = withDbRecovery {
        val meta = attachments.map { att ->
            DbAttachmentMeta(
                id = att.id,
                kind =
                    when (att.type) {
                        AttachmentType.Image -> DbAttachmentKind.IMAGE
                        AttachmentType.Document -> DbAttachmentKind.DOCUMENT
                    },
                size = att.sizeBytes,
                name = att.name,
            )
        }

        val message =
            db.insertMessage(
                sessionUuid = sessionId,
                sender =
                    if (author == MessageAuthor.User) {
                        DbSender.SELF_USER
                    } else {
                        DbSender.OTHER
                    },
                text = text,
                parentMessageUuid = parentId,
                attachments = meta,
            )

        toMessage(message, attachments)
    }

    internal class PreparedConversation(val owner: EnsuDb, val work: ConversationPreparation)

    internal fun startFollowup(sessionId: String, path: List<String>, userText: String) =
        withDbRecovery {
            db.startConversationFollowup(sessionId, path, userText)
        }

    internal fun prepareConversation(
        context: LlmContext,
        request: ConversationRequest,
    ): PreparedConversation = withDbRecovery {
        PreparedConversation(db, db.prepareConversation(context, request))
    }

    private fun checkConversationOwner(prepared: PreparedConversation) {
        check(db === prepared.owner && dbFile.exists()) { "Conversation changed; retry the reply" }
    }

    internal fun validateConversation(prepared: PreparedConversation) {
        checkConversationOwner(prepared)
        prepared.work.validate()
    }

    internal fun insertPreparedAnswer(
        prepared: PreparedConversation,
        text: String,
    ): ChatMessage {
        checkConversationOwner(prepared)
        return toMessage(prepared.work.finish(text, emptyList()).message, emptyList())
    }

    internal fun applyToolCalls(prepared: PreparedConversation): TodoTurn {
        checkConversationOwner(prepared)
        val finished = prepared.work.finish("", emptyList())
        return TodoTurn(
            reply = toMessage(finished.message, emptyList()),
            status = checkNotNull(finished.toolTurn),
        )
    }

    fun confirmToolTurn(replyId: String): ToolTurnStatus = withDbRecovery {
        db.confirmToolTurn(replyId)
    }

    fun undoToolTurn(replyId: String): ToolTurnStatus = withDbRecovery { db.undoToolTurn(replyId) }

    fun toolTurnStatuses(sessionId: String): Map<String, ToolTurnStatus> = withDbRecovery {
        db.toolTurnStatuses(sessionId)
    }

    fun listTodos(): List<TodoItem> = withDbRecovery { db.listTodos() }

    fun createTodo(title: String, dueAtMs: Long?): TodoItem = withDbRecovery {
        db.createTodo(title, dueAtMs)
    }

    fun updateTodo(todo: TodoItem, title: String, dueAtMs: Long?): TodoItem = withDbRecovery {
        db.updateTodo(todo.id, todo.version, title, dueAtMs)
    }

    fun setTodoCompleted(todo: TodoItem, completed: Boolean): TodoItem = withDbRecovery {
        db.setTodoCompleted(todo.id, todo.version, completed)
    }

    fun deleteTodo(todo: TodoItem) = withDbRecovery { db.deleteTodo(todo.id, todo.version) }

    fun updateMessageText(messageId: String, text: String) = withDbRecovery {
        db.updateMessageText(messageId, text)
    }

    fun updateSessionTitle(sessionId: String, title: String) = withDbRecovery {
        db.updateSessionTitle(sessionId, title)
    }

    private fun toMessage(message: DbMessage, attachments: List<Attachment>) =
        ChatMessage(
            id = message.uuid,
            sessionId = message.sessionUuid,
            parentId = message.parentMessageUuid,
            author =
                when (message.sender) {
                    DbSender.SELF_USER -> MessageAuthor.User
                    DbSender.OTHER -> MessageAuthor.Assistant
                },
            text = message.text,
            timestampMillis = message.createdAtUs / 1000,
            attachments = attachments,
        )

    private fun openDb(dbFile: File, key: ByteArray): EnsuDb {
        return EnsuDb.open(
                dbFile.absolutePath,
                key,
            )
            .also { opened ->
                opened.observeTools(
                    object : ToolsObserver {
                        override fun onChange() = onToolsChanged()
                    }
                )
            }
    }

    private fun <T> withDbRecovery(block: () -> T): T {
        if (!dbFile.exists()) {
            reopenDb()
        }
        return try {
            block()
        } catch (error: DbException) {
            if (isReadonlyDbError(error)) {
                reopenDb()
                return block()
            }
            throw error
        }
    }

    private fun reopenDb() {
        dbFile.parentFile?.mkdirs()
        dbFile.setWritable(true)
        db = openDb(dbFile, dbKey)
    }

    private fun pruneOrphanedAttachments() {
        val referenced =
            try {
                db.listSessions()
                    .flatMap { session -> db.getMessages(session.uuid) }
                    .flatMap { message -> message.attachments }
                    .mapTo(mutableSetOf()) { attachment -> attachment.id }
            } catch (_: DbException) {
                return
            }
        attachmentsDir.listFiles()?.forEach { file ->
            if (file.isFile && file.name !in referenced) file.delete()
        }
    }

    private fun isReadonlyDbError(error: DbException): Boolean {
        return error is DbException.ReadonlyDatabase
    }
}
