package io.ente.ensu.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import org.json.JSONObject

class SessionPreferencesDataStore(context: Context) {
    private val dataStore: DataStore<Preferences> = getDataStore(context.applicationContext)

    val selectedSessionId: Flow<String?> = dataStore.data.map { preferences ->
        preferences[Keys.SELECTED_SESSION_ID]
    }

    val sessionSummaries: Flow<Map<String, String>> = dataStore.data.map { preferences ->
        decodeSessionSummaries(preferences[Keys.SESSION_SUMMARIES])
    }

    val modelDownloadRequested: Flow<Boolean> = dataStore.data.map { preferences ->
        preferences[Keys.MODEL_DOWNLOAD_REQUESTED] ?: false
    }

    suspend fun setSelectedSessionId(sessionId: String?) {
        dataStore.edit { preferences ->
            if (sessionId == null) {
                preferences.remove(Keys.SELECTED_SESSION_ID)
            } else {
                preferences[Keys.SELECTED_SESSION_ID] = sessionId
            }
        }
    }

    suspend fun setSessionSummary(sessionId: String, summary: String?) {
        dataStore.edit { preferences ->
            val summaries = decodeSessionSummaries(preferences[Keys.SESSION_SUMMARIES]).toMutableMap()
            if (summary.isNullOrBlank()) {
                summaries.remove(sessionId)
            } else {
                summaries[sessionId] = summary
            }
            preferences[Keys.SESSION_SUMMARIES] = encodeSessionSummaries(summaries)
        }
    }

    suspend fun setModelDownloadRequested(requested: Boolean) {
        dataStore.edit { preferences ->
            preferences[Keys.MODEL_DOWNLOAD_REQUESTED] = requested
        }
    }

    private fun decodeSessionSummaries(raw: String?): Map<String, String> {
        if (raw.isNullOrBlank()) return emptyMap()
        return runCatching {
            val json = JSONObject(raw)
            val map = mutableMapOf<String, String>()
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val value = json.optString(key)
                if (value.isNotBlank()) {
                    map[key] = value
                }
            }
            map
        }.getOrDefault(emptyMap())
    }

    private fun encodeSessionSummaries(summaries: Map<String, String>): String {
        val json = JSONObject()
        summaries.forEach { (key, value) ->
            json.put(key, value)
        }
        return json.toString()
    }

    private object Keys {
        val SELECTED_SESSION_ID = stringPreferencesKey("selected_session_id")
        val SESSION_SUMMARIES = stringPreferencesKey("session_summaries")
        val MODEL_DOWNLOAD_REQUESTED = booleanPreferencesKey("model_download_requested")
    }

    companion object {
        @Volatile
        private var instance: DataStore<Preferences>? = null

        private fun getDataStore(context: Context): DataStore<Preferences> {
            return instance ?: synchronized(this) {
                instance ?: PreferenceDataStoreFactory.create {
                    context.preferencesDataStoreFile("ensu_session_prefs")
                }.also { created ->
                    instance = created
                }
            }
        }
    }
}
