package io.ente.ensu.notes

import android.content.ContentResolver
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.provider.DocumentsContract
import io.ente.ensu.bindings.NotesCancellationInterface
import io.ente.ensu.bindings.NotesDocument
import io.ente.ensu.bindings.NotesException
import io.ente.ensu.bindings.NotesRead
import io.ente.ensu.bindings.NotesSource
import io.ente.ensu.bindings.notesLimits
import io.ente.ensu.bindings.validateNotesDocumentId
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.atomic.AtomicReference

private const val MAX_SCAN_ENTRIES = 250_000

internal class AndroidNotesSource(
    private val resolver: ContentResolver,
    private val tree: Uri,
    private val cancellation: NotesCancellationInterface
) : NotesSource {
    @Volatile private var signal: CancellationSignal? = null
    private val activeRead = AtomicReference<FileChannel?>()
    private val rootId = DocumentsContract.getTreeDocumentId(tree)
    private val limits = notesLimits()
    private val directories = mutableMapOf<String, Map<String, Entry>>()
    private var supportsPath = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

    data class Entry(
        val id: String,
        val name: String,
        val directory: Boolean,
        val size: Long?,
        val modified: Long?,
        val virtual: Boolean
    )

    fun cancel() {
        cancellation.cancel()
        try {
            signal?.cancel()
        } finally {
            runCatching { activeRead.getAndSet(null)?.close() }
        }
    }

    private fun uri(id: String) = DocumentsContract.buildDocumentUriUsingTree(tree, id)

    private fun query(target: Uri): List<Entry> = access { request ->
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_FLAGS
        )
        resolver.query(target, columns, null, null, null, request)?.use { cursor ->
            val entries = mutableListOf<Entry>()
            while (cursor.moveToNext()) {
                request.throwIfCanceled()
                if (entries.size % 64 == 0) cancellation.check()
                if (entries.size >= MAX_SCAN_ENTRIES) throw NotesException.InvalidInput("The Notes folder contains too many entries")
                val id = cursor.getString(0) ?: throw NotesException.SourceRead("Missing document identity")
                val name = cursor.getString(1) ?: throw NotesException.SourceRead("Missing document name")
                entries += Entry(
                    id = id,
                    name = name,
                    directory = cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR,
                    size = if (cursor.isNull(3)) null else cursor.getLong(3).takeIf { it >= 0 },
                    modified = if (cursor.isNull(4)) null else cursor.getLong(4).takeIf { it > 0 },
                    virtual = !cursor.isNull(5) && cursor.getInt(5) and DocumentsContract.Document.FLAG_VIRTUAL_DOCUMENT != 0
                )
            }
            if (cursor.extras.containsKey(DocumentsContract.EXTRA_ERROR)) {
                throw NotesException.SourceRead("Could not load the complete Notes folder. Please try again.")
            }
            if (cursor.extras.getBoolean(DocumentsContract.EXTRA_LOADING, false)) {
                throw NotesException.SourceRead("The folder is still loading. Please try again.")
            }
            entries
        } ?: throw NotesException.SourceRead("Could not read the Notes folder")
    }

    private fun children(id: String): Map<String, Entry> = directories.getOrPut(id) {
        queryChildren(id)
    }

    private fun queryChildren(id: String): Map<String, Entry> {
        val entries = query(DocumentsContract.buildChildDocumentsUriUsingTree(tree, id))
        val children = entries.associateBy { it.name }
        if (children.size != entries.size) {
            throw NotesException.SourceRead("The folder contains duplicate document names")
        }
        return children
    }

    fun sameRoot(other: AndroidNotesSource): Boolean =
        tree.authority == other.tree.authority && rootId == other.rootId

    fun root(): Entry =
        query(uri(rootId)).singleOrNull()?.takeIf { it.directory } ?: throw NotesException.Unavailable()

    fun contains(other: AndroidNotesSource): Boolean {
        if (tree.authority != other.tree.authority) return false
        val pending = ArrayDeque<String>()
        val seen = mutableSetOf<String>()
        var count = 0
        pending.add(rootId)
        while (pending.isNotEmpty()) {
            cancellation.check()
            val id = pending.removeFirst()
            if (id == other.rootId) return true
            if (!seen.add(id)) throw NotesException.SourceRead("Ambiguous directory structure")
            for (child in children(id).values) {
                if (++count > MAX_SCAN_ENTRIES) throw NotesException.InvalidInput("The Notes folder contains too many entries")
                if (child.id == other.rootId) return true
                if (child.directory) pending.add(child.id)
            }
        }
        return false
    }

    override fun listDocuments(): List<NotesDocument> {
        root()
        val pending = ArrayDeque<Pair<String, String>>()
        val seen = mutableSetOf<String>()
        val documents = mutableListOf<NotesDocument>()
        var entries = 0
        var total = 0L
        pending.add(rootId to "")
        while (pending.isNotEmpty()) {
            cancellation.check()
            val (directory, prefix) = pending.removeFirst()
            if (!seen.add(directory)) throw NotesException.SourceRead("Ambiguous directory structure")
            for (child in children(directory).values) {
                if (++entries > MAX_SCAN_ENTRIES) throw NotesException.InvalidInput("The Notes folder contains too many entries")
                if (child.name.startsWith(".")) continue
                if (!child.directory && (child.virtual || !supported(child.name))) continue
                if (child.name.contains("/")) continue
                val id = prefix + child.name
                try {
                    validateNotesDocumentId(id)
                } catch (_: NotesException.InvalidInput) {
                    continue
                }
                if (child.directory) {
                    pending.add(child.id to "$id/")
                } else {
                    if (child.size != null && child.size > limits.maxSourceBytes.toLong()) continue
                    val size = child.size ?: try {
                        bytes(child.id).size.toLong()
                    } catch (_: TooLarge) {
                        continue
                    }
                    total += size
                    if (documents.size.toULong() >= limits.maxCollectionDocuments || total.toULong() > limits.maxCollectionSourceBytes) {
                        throw NotesException.InvalidInput("The Notes folder is too large to index")
                    }
                    documents += NotesDocument(id, size.toULong(), child.modified)
                }
            }
        }
        return documents.sortedBy { it.documentId }
    }

    private fun resolve(documentId: String): Entry {
        validateNotesDocumentId(documentId)
        root()
        var directory = rootId
        val expectedPath = mutableListOf(rootId)
        val parts = documentId.split("/")
        for ((index, name) in parts.withIndex()) {
            if (name.startsWith(".")) throw NotesException.SourceChanged()
            val expected = children(directory)[name] ?: throw NotesException.SourceChanged()
            val entry = query(uri(expected.id)).singleOrNull() ?: throw NotesException.SourceChanged()
            if (entry.id != expected.id || entry.name != expected.name || entry.directory != expected.directory) {
                throw NotesException.SourceChanged()
            }
            expectedPath += entry.id
            if (index == parts.lastIndex) {
                if (entry.directory || entry.virtual || !supported(name)) throw NotesException.SourceChanged()
                if (!verifyPath(entry.id, expectedPath)) {
                    verifyListedPath(expectedPath, parts)
                }
                return entry
            }
            if (!entry.directory) throw NotesException.SourceChanged()
            directory = entry.id
        }
        throw NotesException.SourceChanged()
    }

    private fun verifyPath(id: String, expected: List<String>): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !supportsPath) return false
        return access {
            try {
                val path = DocumentsContract.findDocumentPath(resolver, uri(id))
                    ?: throw NotesException.SourceRead("Could not verify the note location. Please try again.")
                if (path.path != expected) throw NotesException.SourceChanged()
                true
            } catch (_: UnsupportedOperationException) {
                supportsPath = false
                false
            }
        }
    }

    private fun verifyListedPath(expected: List<String>, names: List<String>) {
        for ((index, name) in names.withIndex()) {
            val entry = queryChildren(expected[index])[name] ?: throw NotesException.SourceChanged()
            if (entry.id != expected[index + 1]) throw NotesException.SourceChanged()
        }
    }

    override fun readDocument(documentId: String): NotesRead {
        val before = resolve(documentId)
        val bytes = try {
            bytes(before.id)
        } catch (_: TooLarge) {
            throw NotesException.SourceChanged()
        }
        val after = resolve(documentId)
        if (before != after || (after.size != null && after.size != bytes.size.toLong())) {
            throw NotesException.SourceChanged()
        }
        return NotesRead(bytes, NotesDocument(documentId, bytes.size.toULong(), after.modified))
    }

    private fun bytes(id: String): ByteArray = access { request ->
        val descriptor = resolver.openAssetFileDescriptor(uri(id), "r", request)
            ?: throw NotesException.SourceRead("Could not read the note")
        descriptor.use {
            cancellation.check()
            it.createInputStream().use { input ->
                val channel = input.channel
                activeRead.set(channel)
                try {
                    cancellation.check()
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    val destination = ByteBuffer.wrap(buffer)
                    var remaining = descriptor.declaredLength.takeIf { length -> length >= 0 } ?: Long.MAX_VALUE
                    while (remaining > 0) {
                        cancellation.check()
                        destination.clear()
                        destination.limit(minOf(buffer.size.toLong(), remaining).toInt())
                        val count = channel.read(destination)
                        if (count < 0) {
                            if (descriptor.parcelFileDescriptor.canDetectErrors()) {
                                descriptor.parcelFileDescriptor.checkError()
                            }
                            break
                        }
                        if (output.size() + count > limits.maxSourceBytes.toLong()) throw TooLarge()
                        output.write(buffer, 0, count)
                        remaining -= count
                    }
                    output.toByteArray()
                } finally {
                    activeRead.compareAndSet(channel, null)
                }
            }
        }
    }

    private fun <T> access(block: (CancellationSignal) -> T): T {
        cancellation.check()
        val request = CancellationSignal()
        signal = request
        try {
            cancellation.check()
            return block(request).also { cancellation.check() }
        } catch (e: NotesException) {
            throw e
        } catch (e: TooLarge) {
            throw e
        } catch (_: SecurityException) {
            throw NotesException.Unavailable()
        } catch (_: FileNotFoundException) {
            cancellation.check()
            throw NotesException.SourceRead("The note is currently unavailable. Please try again.")
        } catch (_: Exception) {
            cancellation.check()
            throw NotesException.SourceRead("Could not access the Notes folder. Please try again.")
        } finally {
            signal = null
        }
    }

    private class TooLarge : Exception()
    private fun supported(name: String) = name.endsWith(".md", true) || name.endsWith(".markdown", true)
}
