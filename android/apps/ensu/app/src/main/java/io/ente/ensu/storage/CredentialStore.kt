package io.ente.ensu.storage

import android.content.Context
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class CredentialStore(context: Context) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs = EncryptedSharedPreferences.create(
        context,
        "ensu_credentials",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun getOrCreateChatDbKey(hasChatData: Boolean): ByteArray {
        prefs.getString(KEY_CHAT_DB_KEY, null)?.let { encoded ->
            val decoded = decode(encoded)
            check(decoded.size == 32) { "Stored chat DB key has invalid length" }
            return decoded
        }
        check(!hasChatData) { "Existing chat data has no encryption key" }

        val generated = ByteArray(32)
        java.security.SecureRandom().nextBytes(generated)
        check(prefs.edit().putString(KEY_CHAT_DB_KEY, encode(generated)).commit())
        return generated
    }

    private fun encode(bytes: ByteArray): String {
        return Base64.encodeToString(bytes, Base64.NO_WRAP or Base64.URL_SAFE)
    }

    private fun decode(encoded: String): ByteArray {
        return Base64.decode(encoded, Base64.NO_WRAP or Base64.URL_SAFE)
    }

    companion object {
        private const val KEY_CHAT_DB_KEY = "chat_db_key"
    }
}
