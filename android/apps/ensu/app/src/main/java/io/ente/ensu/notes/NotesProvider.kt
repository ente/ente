package io.ente.ensu.notes

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.util.AtomicFile
import androidx.core.content.FileProvider
import io.ente.ensu.bindings.LlmContext
import io.ente.ensu.bindings.NoteSourceReference
import io.ente.ensu.bindings.NotesCancellation
import io.ente.ensu.bindings.NotesCollection
import io.ente.ensu.bindings.NotesException
import io.ente.ensu.bindings.NotesIndexOptions
import io.ente.ensu.bindings.NotesProgressCallback
import io.ente.ensu.bindings.notesContentRevision
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID

internal data class NotesRegistration(
    val id: String,
    val label: String
)

class NotesProvider(private val context: Context) {
    private data class Registration(val id: String, val label: String, val tree: String) {
        fun summary() = NotesRegistration(id, label)
    }

    private val registrations = linkedMapOf<String, Registration>()
    private val root = File(context.noBackupFilesDir, "notes")
    private val registry = AtomicFile(File(root, "collections.json"))
    private val diskGate = Mutex()

    private suspend fun <T> withAccess(block: suspend () -> T): T = withContext(Dispatchers.IO) {
        diskGate.withLock { block() }
    }

    internal suspend fun load(): List<NotesRegistration> = withAccess {
        val records = loadRegistry()
        registrations.clear()
        registrations.putAll(records.associateBy { it.id })
        records.map { it.summary() }
    }

    internal suspend fun inspect(id: String) = withAccess {
        registration(id)
        handle(id).use { it.inspect() }
    }

    internal suspend fun add(tree: Uri): NotesRegistration = withAccess {
        val alreadyGranted = context.contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isReadPermission
        }
        var committed = false
        try {
            context.contentResolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            NotesCancellation().use { token ->
                val source = AndroidNotesSource(context.contentResolver, tree, token)
                val label = source.root().name
                for (registered in registrations.values) {
                    val other = AndroidNotesSource(context.contentResolver, Uri.parse(registered.tree), token)
                    val overlaps = source.sameRoot(other) || source.contains(other) || try {
                        other.contains(source)
                    } catch (_: NotesException.Unavailable) {
                        false
                    } catch (_: NotesException.SourceRead) {
                        false
                    }
                    if (overlaps) {
                        throw NotesException.InvalidInput("This folder overlaps a folder already added to Your Notes.")
                    }
                }
                val record = Registration(UUID.randomUUID().toString(), label, tree.toString())
                save(registrations.values.toList() + record)
                committed = true
                registrations[record.id] = record
                record.summary()
            }
        } catch (error: Exception) {
            if (!committed && !alreadyGranted) {
                runCatching {
                    context.contentResolver.releasePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
            throw error
        }
    }

    internal suspend fun remove(id: String) = withAccess {
        val record = registration(id)
        val remaining = registrations.values.filter { it.id != id }
        save(remaining)
        registrations.remove(id)
        runCatching { handle(id).use { it.remove() } }
        if (remaining.none { it.tree == record.tree }) {
            runCatching {
                context.contentResolver.releasePersistableUriPermission(
                    Uri.parse(record.tree), Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            }
        }
    }

    internal suspend fun search(id: String, query: List<Float>) = withAccess {
        registration(id)
        handle(id).use { it.search(query) }
    }

    internal suspend fun inspectFreshness(id: String, cancel: NotesCancellation) = withAccess {
        withSource(registration(id), cancel) { source ->
            handle(id).use { it.inspectFreshness(source, cancel) }
        }
    }

    internal suspend fun index(
        id: String,
        embedding: LlmContext,
        cancel: NotesCancellation,
        progress: NotesProgressCallback,
        options: NotesIndexOptions
    ) = withAccess {
        withSource(registration(id), cancel) { source ->
            handle(id).use { it.index(source, embedding, cancel, progress, options) }
        }
    }

    private suspend fun <T> withSource(
        record: Registration,
        cancel: NotesCancellation,
        block: (AndroidNotesSource) -> T
    ): T {
        val source = AndroidNotesSource(context.contentResolver, Uri.parse(record.tree), cancel)
        return runNotesRead(source::cancel) { block(source) }
    }

    internal suspend fun verify(reference: NoteSourceReference) = withAccess {
        readVerified(registration(reference.collectionId), reference)
        Unit
    }

    private suspend fun readVerified(record: Registration, reference: NoteSourceReference): ByteArray =
        NotesCancellation().use { cancel ->
            val bytes = withSource(record, cancel) { it.readDocument(reference.documentId) }.bytes
            if (notesContentRevision(bytes) != reference.indexedRevision) throw NotesException.SourceChanged()
            bytes
        }

    internal suspend fun preview(reference: NoteSourceReference): Uri = withAccess {
        val bytes = readVerified(registration(reference.collectionId), reference)
        val previews = File(context.cacheDir, "note-previews").apply { mkdirs() }
        previews.listFiles()?.filter { it.lastModified() < System.currentTimeMillis() - 86_400_000L }
            ?.forEach { it.deleteRecursively() }
        val folder = File(previews, UUID.randomUUID().toString()).apply { mkdirs() }
        val file = File(folder, reference.documentId.substringAfterLast('/')).apply { writeBytes(bytes) }
        FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file)
    }

    private fun registration(id: String): Registration =
        registrations[id] ?: throw NotesException.Unavailable()

    private fun handle(id: String) = NotesCollection(root.absolutePath, id)

    private fun loadRegistry(): List<Registration> {
        if (!registry.baseFile.exists() && !File(registry.baseFile.path + ".bak").exists()) return emptyList()
        val bytes = registry.openRead().use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                require(output.size() + count <= 1024 * 1024)
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }
        val json = JSONObject(bytes.toString(Charsets.UTF_8))
        require(json.getInt("schemaVersion") == 1)
        val records = json.getJSONArray("collections")
        val result = (0 until records.length()).map { i ->
            val row = records.getJSONObject(i)
            val id = row.getString("id")
            require(UUID.fromString(id).toString() == id)
            val tree = row.getString("tree")
            val uri = Uri.parse(tree)
            require(uri.scheme == "content" && DocumentsContract.isTreeUri(uri))
            Registration(id, row.getString("label"), tree)
        }
        val registeredIds = result.map { it.id }.toSet()
        require(registeredIds.size == result.size)
        root.listFiles()?.forEach { child ->
            if (child.name !in registeredIds && runCatching { UUID.fromString(child.name).toString() == child.name }.getOrDefault(false)) {
                runCatching { handle(child.name).use { it.remove() } }
            }
        }
        return result
    }

    private fun save(records: List<Registration>) {
        root.mkdirs()
        val json = JSONObject().put("schemaVersion", 1).put("collections", JSONArray().apply {
            records.forEach {
                put(JSONObject().put("id", it.id).put("label", it.label).put("tree", it.tree))
            }
        })
        val bytes = json.toString().toByteArray()
        require(bytes.size <= 1024 * 1024)
        val stream = registry.startWrite()
        try {
            stream.write(bytes)
            registry.finishWrite(stream)
        } catch (error: Exception) {
            registry.failWrite(stream)
            throw error
        }
    }
}
