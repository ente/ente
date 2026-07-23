package io.ente.install_source

import android.content.Context
import java.net.URLDecoder
import java.util.UUID
import org.json.JSONObject

data class InstallSource(
    val referrerParams: Map<String, String>,
) {
    val hasReferrer: Boolean get() = referrerParams.isNotEmpty()
    val hasNonOrganicReferrer: Boolean
        get() = hasReferrer && !(
            referrerParams["utm_source"] == "google-play" &&
                referrerParams["utm_medium"] == "organic"
            )
}

class InstallSourceEventStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("install_source_state", Context.MODE_PRIVATE)

    fun sourceFromState(): InstallSource? {
        val sourceJson = prefs.getString(KEY_SOURCE, null) ?: return null
        return runCatching {
            val json = JSONObject(sourceJson)
            val paramsJson = json.optJSONObject("referrer_params")
            val params = buildMap {
                paramsJson?.keys()?.forEach { key ->
                    put(key, paramsJson.optString(key))
                }
            }
            InstallSource(referrerParams = params)
        }.getOrNull()
    }

    fun playSource(referrer: String?): InstallSource = InstallSource(
        referrerParams = parseReferrerParams(referrer),
    )

    fun saveSource(source: InstallSource) {
        prefs.edit()
            .putString(KEY_SOURCE, source.toJson().toString())
            .putInt(KEY_FLAGS, sourceFlags(source))
            .apply()
    }

    fun autoAttributeSource(isSignUp: Boolean) {
        prefs.edit()
            .putInt(KEY_FLAGS, flags or if (isSignUp) FLAG_SIGNED_UP else FLAG_LOGGED_IN)
            .apply()
    }

    fun pendingEventJsons(source: InstallSource): List<String> {
        if (!source.hasReferrer) {
            return emptyList()
        }
        val eventId = eventId()
        return buildList {
            if (!flags.hasFlag(FLAG_SENT_INSTALL_SOURCE)) {
                add(buildEvent(source, eventId, EVENT_INSTALL).toString())
            }
            if (!flags.hasFlag(FLAG_LINKED_INSTALL_SOURCE)) {
                userEvent()?.let {
                    add(buildEvent(source, eventId, it).toString())
                }
            }
        }
    }

    fun markEventSent(event: String) {
        when {
            event == EVENT_INSTALL -> prefs.edit()
                .putInt(KEY_FLAGS, flags or FLAG_SENT_INSTALL_SOURCE)
                .apply()
            isUserEvent(event) -> prefs.edit()
                .putInt(KEY_FLAGS, flags or FLAG_LINKED_INSTALL_SOURCE)
                .apply()
        }
    }

    private fun buildEvent(source: InstallSource, eventId: String, event: String): JSONObject =
        JSONObject()
            .put("id", eventId)
            .put("event", event)
            .put(
                "data",
                if (event == EVENT_INSTALL) JSONObject(source.referrerParams) else JSONObject()
            )

    private fun eventId(): String =
        prefs.getString(KEY_EVENT_ID, null) ?: UUID.randomUUID().toString().also {
            prefs.edit().putString(KEY_EVENT_ID, it).apply()
        }

    private fun sourceFlags(source: InstallSource): Int {
        val sourceFlag = if (source.hasReferrer) FLAG_HAS_INSTALL_SOURCE else FLAG_NO_INSTALL_SOURCE
        return (flags and SOURCE_FLAGS.inv()) or sourceFlag
    }

    private fun userEvent(): String? =
        when {
            flags.hasFlag(FLAG_SIGNED_UP) -> EVENT_SIGN_UP
            flags.hasFlag(FLAG_LOGGED_IN) -> EVENT_LOG_IN
            else -> null
        }

    private fun isUserEvent(event: String): Boolean =
        event == EVENT_SIGN_UP || event == EVENT_LOG_IN

    private fun parseReferrerParams(referrer: String?): Map<String, String> {
        val query = referrer?.trim()?.removePrefix("?")
        if (query.isNullOrEmpty()) {
            return emptyMap()
        }
        return runCatching {
            query.split("&")
                .asSequence()
                .filter { it.isNotBlank() }
                .mapNotNull { part ->
                    val separator = part.indexOf("=")
                    val key = if (separator >= 0) part.substring(0, separator) else part
                    val value = if (separator >= 0) part.substring(separator + 1) else ""
                    val decodedKey = key.urlDecode()
                    if (decodedKey.isEmpty()) {
                        null
                    } else {
                        decodedKey to value.urlDecode()
                    }
                }
                .toMap()
        }.getOrDefault(emptyMap())
    }

    private fun InstallSource.toJson(): JSONObject = JSONObject()
        .put("referrer_params", JSONObject(referrerParams))

    private fun String.urlDecode(): String =
        URLDecoder.decode(this, Charsets.UTF_8.name())

    private val flags: Int get() = prefs.getInt(KEY_FLAGS, 0)

    private fun Int.hasFlag(flag: Int): Boolean = this and flag != 0

    companion object {
        private const val EVENT_INSTALL = "install"
        private const val EVENT_LOG_IN = "log_in"
        private const val EVENT_SIGN_UP = "sign_up"
        private const val FLAG_HAS_INSTALL_SOURCE = 1 shl 0
        private const val FLAG_NO_INSTALL_SOURCE = 1 shl 1
        private const val FLAG_SENT_INSTALL_SOURCE = 1 shl 2
        private const val FLAG_LOGGED_IN = 1 shl 3
        private const val FLAG_SIGNED_UP = 1 shl 4
        private const val FLAG_LINKED_INSTALL_SOURCE = 1 shl 5
        private const val SOURCE_FLAGS = FLAG_HAS_INSTALL_SOURCE or FLAG_NO_INSTALL_SOURCE
        private const val KEY_EVENT_ID = "event_id"
        private const val KEY_FLAGS = "flags"
        private const val KEY_SOURCE = "source"
    }
}
