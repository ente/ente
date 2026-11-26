package io.ente.auth.watch

import android.content.Context
import com.google.gson.JsonObject
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

internal class DeviceFile(private val file: File) {
    fun read(): ByteArray? = if (file.exists()) file.readBytes() else null
    fun write(data: ByteArray) {
        require(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs())
        val temporary = File(file.parentFile, file.name + ".new")
        FileOutputStream(temporary).use { it.write(data); it.fd.sync() }
        check(temporary.renameTo(file))
    }
    fun remove() { check(!file.exists() || file.delete()) }
}

internal class VaultEpoch(file: File) {
    private val storage = DeviceFile(file)
    fun current(): String = storage.read()?.toString(Charsets.UTF_8) ?: advance()
    fun advance(): String = UUID.randomUUID().toString().also { storage.write(it.toByteArray()) }
}

internal class WatchRepository(context: Context, file: File) {
    private val keys = ProtectedKeyStore(context)
    data class State(val enrollment: Enrollment?, val snapshot: Snapshot, val receipt: Receipt?)
    private val storage = DeviceFile(file)

    fun read(): State {
        val key = keys.read()
        val envelope = storage.read()?.let(Envelope::decode)
        if (key == null) {
            if (envelope?.retire == true) return State(null, Snapshot.EMPTY, envelope.receipt)
            storage.remove()
            return State(null, Snapshot.EMPTY, null)
        }
        if (envelope == null) return State(key.enrollment, Snapshot.EMPTY, null)
        val snapshot = envelope.open(key)
        if (envelope.retire) keys.remove()
        return State(if (envelope.retire) null else key.enrollment, snapshot, envelope.receipt)
    }

    fun begin(suite: CipherSuite): Enrollment {
        read().enrollment?.let { return it }
        val key = PrivateKey.generate(suite)
        storage.remove()
        keys.write(key)
        return key.enrollment
    }

    fun apply(data: ByteArray): State {
        val state = read()
        val envelope = Envelope.decode(data)
        val key = keys.read()
        if (key == null) {
            if (state.receipt == envelope.receipt) return state
            throw WatchException("wrongEnrollment")
        }
        envelope.open(key)
        if (state.receipt?.needsReplacement(envelope) == false) return state
        storage.write(envelope.data)
        return read()
    }

    fun erase() {
        keys.remove()
        storage.remove()
    }
}

internal class PhoneRepository(file: File, private val epoch: String) {
    data class Record(val enrollment: Enrollment, val epoch: String, val envelope: Envelope,
                      val desiredDigest: String, val receipt: Receipt?) {
        val delivered: Boolean get() = receipt == envelope.receipt
    }
    private val storage = DeviceFile(file)

    fun read(): Record? {
        val data = storage.read() ?: return null
        val record = try {
            val value = json(data, 80 * 1024)
            Record(Enrollment.decode(value.getAsJsonObject("enrollment")), value.string("epoch"),
                Envelope.decode(value.string("envelope").bytes()), value.string("desiredDigest"),
                value.getAsJsonObject("receipt")?.let(Receipt::decode)).also {
                requireWatch(it.enrollment.id == it.envelope.enrollmentID, "wrongEnrollment")
            }
        } catch (_: Exception) {
            storage.remove()
            return null
        }
        return if (record.epoch != epoch && !record.envelope.retire) emptyAfter(record) else record
    }

    fun approve(enrollment: Enrollment, receipt: Receipt?, retire: Boolean = false): Record {
        val envelope = Envelope.seal(Snapshot.EMPTY, enrollment,
            next(if (receipt?.enrollment == enrollment.id) receipt.revision else 0), retire)
        return Record(enrollment, epoch, envelope, Snapshot.EMPTY.encode().digest(), null).also(::write)
    }

    fun publish(snapshot: Snapshot, retire: Boolean = false): Record {
        val previous = read() ?: throw WatchException("wrongEnrollment")
        requireWatch(!previous.envelope.retire, "wrongEnrollment")
        val digest = snapshot.encode().digest()
        val needsRebase = (previous.receipt?.revision ?: 0) >= previous.envelope.revision && !previous.delivered
        if (!retire && previous.desiredDigest == digest && !needsRebase) return previous
        val envelope = Envelope.seal(snapshot, previous.enrollment,
            next(maxOf(previous.envelope.revision, previous.receipt?.revision ?: 0)), retire)
        return Record(previous.enrollment, epoch, envelope, digest, previous.receipt).also(::write)
    }

    fun acknowledge(receipt: Receipt) {
        val previous = read() ?: return
        if (receipt.enrollment != previous.enrollment.id || receipt == previous.receipt ||
            receipt.revision < (previous.receipt?.revision ?: 0)) return
        val record = previous.copy(receipt = receipt)
        if (!record.delivered && receipt.revision >= record.envelope.revision &&
            record.desiredDigest == Snapshot.EMPTY.encode().digest()) emptyAfter(record) else write(record)
    }

    private fun emptyAfter(previous: Record): Record = Record(previous.enrollment, epoch,
        Envelope.seal(Snapshot.EMPTY, previous.enrollment,
            next(maxOf(previous.envelope.revision, previous.receipt?.revision ?: 0)), previous.envelope.retire),
        Snapshot.EMPTY.encode().digest(), previous.receipt).also(::write)

    private fun next(revision: Long): Long {
        requireWatch(revision < Long.MAX_VALUE, "invalidEnvelope")
        return revision + 1
    }

    private fun write(record: Record) {
        storage.write(JsonObject().apply {
            add("enrollment", record.enrollment.encode()); addProperty("epoch", record.epoch)
            addProperty("envelope", record.envelope.data.base64()); addProperty("desiredDigest", record.desiredDigest)
            record.receipt?.let { add("receipt", it.encode()) }
        }.encode())
    }
}

internal data class WatchStatus(val enrollment: Enrollment?, val receipt: Receipt?, val storageError: Boolean = false) {
    fun encode(): ByteArray = JsonObject().apply {
        addProperty("version", 1)
        enrollment?.let { add("enrollment", it.encode()) }
        receipt?.let { add("receipt", it.encode()) }
        addProperty("storageError", storageError)
    }.encode()

    companion object {
        fun decode(data: ByteArray): WatchStatus {
            val value = json(data, 8192)
            requireWatch(value.number("version") == 1L, "unsupportedVersion")
            return WatchStatus(value.getAsJsonObject("enrollment")?.let(Enrollment::decode),
                value.getAsJsonObject("receipt")?.let(Receipt::decode), value.get("storageError")?.asBoolean == true)
                .also { requireWatch(it.enrollment == null || it.receipt == null ||
                    it.enrollment.id == it.receipt.enrollment, "wrongEnrollment") }
        }
    }
}
