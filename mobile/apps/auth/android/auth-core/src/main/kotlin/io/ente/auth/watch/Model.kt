package io.ente.auth.watch

import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.nio.ByteBuffer
import java.security.MessageDigest
import kotlin.io.encoding.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

class WatchException(val code: String) : Exception(code)

internal fun requireWatch(value: Boolean, code: String) {
    if (!value) throw WatchException(code)
}

internal fun ByteArray.base64(): String = Base64.encode(this)
internal fun String.bytes(): ByteArray = Base64.decode(this)
internal fun ByteArray.digest(): String = MessageDigest.getInstance("SHA-256").digest(this)
    .joinToString("") { "%02x".format(it) }
internal fun JsonObject.string(name: String): String {
    val value = get(name)
    requireWatch(value != null && value.isJsonPrimitive && value.asJsonPrimitive.isString, "invalidEnvelope")
    return value.asString
}
internal fun JsonObject.number(name: String): Long {
    val value = get(name)
    requireWatch(value != null && value.isJsonPrimitive && value.asJsonPrimitive.isNumber, "invalidEnvelope")
    return value.asBigDecimal.longValueExact()
}
internal fun JsonObject.boolean(name: String): Boolean {
    val value = get(name)
    requireWatch(value != null && value.isJsonPrimitive && value.asJsonPrimitive.isBoolean, "invalidEnvelope")
    return value.asBoolean
}
internal fun JsonObject.stringList(name: String): List<String> {
    val value = get(name)
    requireWatch(value != null && value.isJsonArray, "invalidEnvelope")
    return value.asJsonArray.map { element ->
        requireWatch(element.isJsonPrimitive && element.asJsonPrimitive.isString, "invalidEnvelope")
        element.asString
    }
}
internal fun json(data: ByteArray, maximum: Int = Envelope.MAXIMUM_BYTES): JsonObject {
    requireWatch(data.size <= maximum, "payloadTooLarge")
    return JsonParser.parseString(data.toString(Charsets.UTF_8)).asJsonObject
}
internal fun JsonObject.encode(): ByteArray = toString().toByteArray(Charsets.UTF_8)

data class Entry(
    val id: String,
    val issuer: String,
    val account: String,
    val secret: String,
    val generator: String,
    val algorithm: String,
    val digits: Int,
    val period: Int,
    val pinned: Boolean = false,
    val tags: List<String> = emptyList(),
) {
    fun validate() {
        requireWatch(id.isNotEmpty() && secret.bytes().isNotEmpty(), "invalidEntry")
        requireWatch(algorithm in listOf("sha1", "sha256", "sha512"), "invalidEntry")
        when (generator) {
            "totp" -> requireWatch(digits in 1..10 && period > 0, "invalidEntry")
            "steam" -> requireWatch(algorithm == "sha1" && digits == 5 && period == 30, "invalidEntry")
            else -> throw WatchException("invalidEntry")
        }
    }

    fun code(seconds: Long): String {
        requireWatch(seconds >= 0, "invalidEntry")
        val name = when (algorithm) { "sha1" -> "HmacSHA1"; "sha256" -> "HmacSHA256"; else -> "HmacSHA512" }
        val mac = Mac.getInstance(name)
        mac.init(SecretKeySpec(secret.bytes(), name))
        val hash = mac.doFinal(ByteBuffer.allocate(8).putLong(seconds / period).array())
        val offset = hash.last().toInt() and 15
        var value = (ByteBuffer.wrap(hash, offset, 4).int.toLong() and 0x7fffffff)
        if (generator == "steam") {
            val alphabet = "23456789BCDFGHJKMNPQRTVWXY"
            return buildString {
                repeat(5) { append(alphabet[(value % alphabet.length).toInt()]); value /= alphabet.length }
            }
        }
        var modulus = 1L
        repeat(digits) { modulus *= 10 }
        return (value % modulus).toString().padStart(digits, '0')
    }

    internal fun encode() = JsonObject().apply {
        addProperty("id", id); addProperty("issuer", issuer); addProperty("account", account)
        addProperty("secret", secret); addProperty("generator", generator); addProperty("algorithm", algorithm)
        addProperty("digits", digits); addProperty("period", period)
        addProperty("pinned", pinned)
        add("tags", JsonArray().apply { tags.forEach(::add) })
    }

    companion object {
        internal fun decode(value: JsonObject): Entry {
            val digits = value.number("digits")
            val period = value.number("period")
            requireWatch(digits in 1..10 && period in 1..Int.MAX_VALUE, "invalidEntry")
            return Entry(value.string("id"), value.string("issuer"), value.string("account"),
                value.string("secret"), value.string("generator"), value.string("algorithm"),
                digits.toInt(), period.toInt(),
                value.boolean("pinned"),
                value.stringList("tags"))
        }
    }
}

data class Snapshot(val entries: List<Entry>) {
    fun encode(): ByteArray {
        validate()
        return JsonObject().apply {
            add("entries", JsonArray().apply { entries.forEach { add(it.encode()) } })
        }.encode()
    }

    fun validate() {
        requireWatch(entries.map { it.id }.toSet().size == entries.size, "invalidSnapshot")
        entries.forEach { it.validate() }
    }

    companion object {
        val EMPTY = Snapshot(emptyList())
        fun decode(data: ByteArray, maximum: Int = Envelope.MAX_PLAINTEXT_BYTES): Snapshot {
            val root = json(data, maximum)
            val entries = root.getAsJsonArray("entries").map { Entry.decode(it.asJsonObject) }
            return Snapshot(entries).also { it.validate() }
        }
    }
}
