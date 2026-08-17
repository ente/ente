package io.ente.ensu.chat

import android.content.Context
import io.ente.ensu.storage.CredentialStore
import io.ente.ensu.storage.FilePathManager
import io.ente.ensu.chat.Attachment
import io.ente.ensu.chat.AttachmentType
import io.ente.ensu.chat.ChatMessage
import io.ente.ensu.chat.ChatSession
import io.ente.ensu.chat.MessageAuthor
import io.ente.ensu.chat.sessionTitleFromText
import io.ente.ensu.bindings.DbAttachmentKind
import io.ente.ensu.bindings.DbAttachmentMeta
import io.ente.ensu.bindings.DbSender
import io.ente.ensu.bindings.EnsuDb
import io.ente.ensu.bindings.DbException
import io.ente.ensu.bindings.cleanAssistantText
import java.io.File

class ChatRepository(
    context: Context,
    credentialStore: CredentialStore
) {

    private val filePaths = FilePathManager(context)
    private val attachmentsDir = filePaths.attachmentsDir
    private val dbFile = filePaths.mainDbFile
    private val dbKey = credentialStore.getOrCreateChatDbKey(filePaths.hasChatData)
    private var db: EnsuDb = openDb(dbFile, dbKey)

    init {
        pruneOrphanedAttachments()
    }

    fun listSessions(): List<ChatSession> = withDbRecovery {
        val sessions = db.listSessions()
        sessions.map { session ->
            val messages = runCatching { db.getMessages(session.uuid) }.getOrNull().orEmpty()
            val firstMessage = messages.firstOrNull()?.let { message ->
                if (message.sender == DbSender.OTHER) cleanAssistantText(message.text) else message.text
            }.orEmpty()
            val lastMessage = messages.lastOrNull()?.let { message ->
                if (message.sender == DbSender.OTHER) cleanAssistantText(message.text) else message.text
            }
            val isPlaceholder = session.title.isBlank() || session.title.equals("New Chat", ignoreCase = true)
            val seedTitle = if (isPlaceholder) firstMessage else session.title
            ChatSession(
                id = session.uuid,
                title = sessionTitleFromText(seedTitle, fallback = session.title),
                lastMessagePreview = lastMessage,
                updatedAtMillis = session.updatedAtUs / 1000
            )
        }
    }

    fun createSession(title: String): ChatSession = withDbRecovery {
        val session = db.createSession(title)
        ChatSession(
            id = session.uuid,
            title = session.title,
            lastMessagePreview = null,
            updatedAtMillis = session.updatedAtUs / 1000
        )
    }

    fun deleteSession(sessionId: String) = withDbRecovery {
        db.deleteSession(sessionId).forEach { id ->
            File(attachmentsDir, id).delete()
        }
    }

    fun getMessages(sessionId: String): List<ChatMessage> = withDbRecovery {
        db.getMessages(sessionId).map { message ->
            ChatMessage(
                id = message.uuid,
                sessionId = message.sessionUuid,
                parentId = message.parentMessageUuid,
                author = when (message.sender) {
                    DbSender.SELF_USER -> MessageAuthor.User
                    DbSender.OTHER -> MessageAuthor.Assistant
                },
                text = message.text,
                timestampMillis = message.createdAtUs / 1000,
                attachments = message.attachments.map { meta ->
                    val file = File(attachmentsDir, meta.id)
                    Attachment(
                        id = meta.id,
                        name = meta.name,
                        sizeBytes = meta.size,
                        type = when (meta.kind) {
                            DbAttachmentKind.IMAGE -> AttachmentType.Image
                            DbAttachmentKind.DOCUMENT -> AttachmentType.Document
                        },
                        localPath = file.takeIf { it.exists() }?.absolutePath,
                        isUploading = false
                    )
                }
            )
        }
    }

    fun insertMessage(
        sessionId: String,
        parentId: String?,
        author: MessageAuthor,
        text: String,
        attachments: List<Attachment>
    ): ChatMessage = withDbRecovery {
        val meta = attachments.map { att ->
            DbAttachmentMeta(
                id = att.id,
                kind = when (att.type) {
                    AttachmentType.Image -> DbAttachmentKind.IMAGE
                    AttachmentType.Document -> DbAttachmentKind.DOCUMENT
                },
                size = att.sizeBytes,
                name = att.name
            )
        }

        val message = db.insertMessage(
            sessionUuid = sessionId,
            sender = if (author == MessageAuthor.User) {
                DbSender.SELF_USER
            } else {
                DbSender.OTHER
            },
            text = text,
            parentMessageUuid = parentId,
            attachments = meta
        )

        ChatMessage(
            id = message.uuid,
            sessionId = message.sessionUuid,
            parentId = message.parentMessageUuid,
            author = author,
            text = message.text,
            timestampMillis = message.createdAtUs / 1000,
            attachments = attachments
        )
    }

    fun updateMessageText(messageId: String, text: String) = withDbRecovery {
        db.updateMessageText(messageId, text)
    }

    fun updateSessionTitle(sessionId: String, title: String) = withDbRecovery {
        db.updateSessionTitle(sessionId, title)
    }

    private fun openDb(dbFile: File, key: ByteArray): EnsuDb {
        return EnsuDb.open(
            dbFile.absolutePath,
            key
        )
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
        val referenced = try {
            db.listSessions().flatMap { session -> db.getMessages(session.uuid) }
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
