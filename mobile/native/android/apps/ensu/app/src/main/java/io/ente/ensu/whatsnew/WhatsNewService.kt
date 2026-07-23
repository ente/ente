package io.ente.ensu.whatsnew

import android.content.Context

data class PendingWhatsNew(
    val version: Int,
    val entries: List<WhatsNewEntry>
)

class WhatsNewService(context: Context) {
    private val preferences = context.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE
    )

    fun getPendingWhatsNew(): PendingWhatsNew? {
        if (!preferences.contains(KEY_SEEN_VERSION)) {
            markSeen()
            return null
        }

        val seenVersion = preferences.getInt(KEY_SEEN_VERSION, WhatsNewContent.VERSION)
        if (seenVersion >= WhatsNewContent.VERSION) return null

        if (WhatsNewContent.entries.isEmpty()) {
            markSeen()
            return null
        }

        return PendingWhatsNew(
            version = WhatsNewContent.VERSION,
            entries = WhatsNewContent.entries
        )
    }

    fun markSeen() {
        preferences.edit()
            .putInt(KEY_SEEN_VERSION, WhatsNewContent.VERSION)
            .apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "ensu_whats_new"
        const val KEY_SEEN_VERSION = "seen_version"
    }
}
