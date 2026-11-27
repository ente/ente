package io.ente.auth.watch

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

class PhoneCompanion(context: Context) {
    enum class Phase { unavailable, setup, approval, pending, synced, retiring, disabled, failed, replacement, ambiguous }
    data class State(val phase: Phase = Phase.unavailable, val enrollmentID: String? = null,
                     val requestID: String? = null, val vaultEpoch: String? = null)
    private val directory = File(context.noBackupFilesDir, "watch")
    private val epoch = VaultEpoch(File(directory, "epoch"))
    private val transport = DataLayer(context.applicationContext)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var foreground = false
    private var state = State()
    private var requested: WatchStatus? = null
    var onChange: ((State) -> Unit)? = null

    fun setForeground(value: Boolean) {
        foreground = value
        enqueue {
            if (value) refresh() else transport.stop()
        }
    }

    fun readState(completion: (Result<State>) -> Unit) = execute(completion) { refresh() }

    fun approve(id: String, completion: (Result<State>) -> Unit) = change(completion) {
        val repository = repository()
        val record = repository.read()
        val watch = requested ?: throw WatchException("wrongEnrollment")
        requireWatch(state.phase == Phase.approval && watch.enrollment?.id == id &&
            (record == null || record.envelope.retire), "wrongEnrollment")
        repository.approve(watch.enrollment!!, watch.receipt)
    }

    fun publish(snapshot: Snapshot, id: String, expectedEpoch: String,
                completion: (Result<State>) -> Unit) = change(completion) {
        requireWatch(expectedEpoch == epoch.current(), "staleVault")
        val repository = repository()
        val record = repository.read()
        requireWatch(id == record?.enrollment?.id && requested?.enrollment?.id == id &&
            !record.envelope.retire, "wrongEnrollment")
        repository.publish(snapshot)
    }

    fun disable(id: String, completion: (Result<State>) -> Unit) = change(completion) {
        val repository = repository()
        val record = repository.read() ?: throw WatchException("wrongEnrollment")
        requireWatch(record.enrollment.id == id, "wrongEnrollment")
        if (!record.envelope.retire) repository.publish(Snapshot.EMPTY, retire = true)
    }

    fun clear(completion: (Result<State>) -> Unit) = enqueue {
        try {
            epoch.advance()
            val record = repository().read()
            update(State(if (record == null) Phase.setup else Phase.pending,
                record?.enrollment?.id, vaultEpoch = epoch.current()))
            val cleared = state
            main.post { completion(Result.success(cleared)) }
            sendReset(record)
        } catch (error: Exception) {
            main.post { completion(Result.failure(error)) }
        }
    }

    private fun change(completion: (Result<State>) -> Unit, operation: () -> Unit) = execute(completion) {
        refresh()
        requireWatch(foreground, "phoneLocked")
        operation()
        refresh()
    }

    private fun execute(completion: (Result<State>) -> Unit, operation: () -> Unit) = enqueue {
        val result = try {
            operation()
            Result.success(state)
        } catch (error: Exception) { Result.failure(error) }
        main.post { completion(result) }
    }

    private fun repository() = PhoneRepository(File(directory, "phone-state"), epoch.current())

    private fun refresh() {
        try {
            val currentEpoch = epoch.current()
            val repository = repository()
            var record = repository.read()
            if (!foreground) {
                update(State(Phase.unavailable, record?.enrollment?.id, vaultEpoch = currentEpoch))
                return
            }
            transport.start { enqueue { if (foreground) refresh() } }
            transport.put(DataLayer.CAPABILITIES, JsonObject().apply {
                addProperty("version", 1)
                add("suites", JsonArray().apply { CipherSuite.supported.forEach { add(it.wire) } })
            }.encode())
            send(record)
            val nodes = transport.connectedNodes()
            val statuses = transport.items().filter { it.path == DataLayer.STATUS }.mapNotNull { item ->
                try { item.node to WatchStatus.decode(item.data) } catch (_: Exception) { null }
            }
            statuses.forEach { (_, status) -> status.receipt?.let { repository.acknowledge(it) } }
            record = repository.read()
            val connected = statuses.filter { it.first in nodes }.map { it.second }
            val approvedID = record?.takeUnless { it.envelope.retire }?.enrollment?.id
            val retiringID = record?.takeIf { it.envelope.retire }?.enrollment?.id
            val candidates = connected.filter { it.enrollment != null && it.enrollment.id != retiringID }
                .distinctBy { it.enrollment!!.id }
            requested = connected.firstOrNull { approvedID != null && it.enrollment?.id == approvedID }
                ?: candidates.singleOrNull()
                ?: statuses.firstOrNull { candidates.isEmpty() && approvedID != null &&
                    it.second.enrollment?.id == approvedID }?.second
            val watch = requested
            if (record == null && watch?.enrollment != null && watch.receipt != null) {
                record = repository.approve(watch.enrollment, watch.receipt, retire = true)
            }
            val phase = when {
                watch?.storageError == true -> Phase.failed
                watch == null && candidates.size > 1 -> Phase.ambiguous
                watch?.enrollment != null && watch.enrollment.id != record?.enrollment?.id ->
                    if (record != null && !record.envelope.retire) Phase.replacement else Phase.approval
                record?.envelope?.retire == true -> if (record.delivered) Phase.disabled else Phase.retiring
                record != null -> if (record.delivered && watch?.enrollment?.id == record.enrollment.id)
                    Phase.synced else Phase.pending
                else -> Phase.setup
            }
            send(record)
            update(State(phase, record?.enrollment?.id, watch?.enrollment?.id, currentEpoch))
        } catch (_: Exception) {
            requested = null
            update(State(Phase.unavailable, try { repository().read()?.enrollment?.id } catch (_: Exception) { null },
                vaultEpoch = try { epoch.current() } catch (_: Exception) { null }))
        }
    }

    private fun send(record: PhoneRepository.Record?) {
        record ?: return
        val path = DataLayer.snapshot(record.enrollment.id)
        if (record.envelope.retire && record.delivered) transport.delete(path)
        else transport.put(path, record.envelope.data)
    }

    private fun sendReset(record: PhoneRepository.Record?) {
        try {
            transport.start { enqueue { if (foreground) refresh() } }
            send(record)
        } catch (_: Exception) { } finally { if (!foreground) transport.stop() }
    }

    private fun enqueue(operation: () -> Unit) {
        try { worker.execute(operation) } catch (_: RejectedExecutionException) {
        }
    }

    private fun update(next: State) {
        if (next == state) return
        state = next
        main.post { onChange?.invoke(next) }
    }

    fun close() {
        foreground = false
        onChange = null
        worker.execute { transport.stop() }
        worker.shutdown()
    }
}
