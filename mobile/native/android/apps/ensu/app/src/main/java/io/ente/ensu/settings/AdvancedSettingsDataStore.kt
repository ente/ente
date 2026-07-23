package io.ente.ensu.settings

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import io.ente.ensu.settings.DeveloperSettingsState
import io.ente.ensu.llm.ModelSettingsState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

private val Context.advancedSettingsPreferences by preferencesDataStore("ensu_advanced_settings")

data class AdvancedSettingsSnapshot(
    val developerSettings: DeveloperSettingsState = DeveloperSettingsState(),
    val modelSettings: ModelSettingsState = ModelSettingsState()
)

class AdvancedSettingsDataStore(private val context: Context) {
    private val persistenceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    val settingsFlow: Flow<AdvancedSettingsSnapshot> = context.advancedSettingsPreferences.data.map { prefs ->
        AdvancedSettingsSnapshot(
            developerSettings = DeveloperSettingsState(
                isAdvancedUnlocked = prefs[Keys.advancedUnlocked] ?: false,
                systemPrompt = prefs[Keys.systemPrompt].orEmpty()
            ),
            modelSettings = ModelSettingsState(
                modelId = prefs[Keys.modelId].orEmpty(),
                contextLength = prefs[Keys.contextLength].orEmpty(),
                maxTokens = prefs[Keys.maxTokens].orEmpty(),
                temperature = prefs[Keys.temperature].orEmpty()
            )
        )
    }

    suspend fun migrateLegacyModelSelection(
        migrate: suspend (legacyModelUrl: String?, legacyMmprojUrl: String?) -> String?
    ) {
        val useCustomModel = booleanPreferencesKey("use_custom_model")
        val modelUrl = stringPreferencesKey("model_url")
        val mmprojUrl = stringPreferencesKey("mmproj_url")
        val prefs = context.advancedSettingsPreferences.data.first()
        val pending = prefs[Keys.modelId] == null
        val url = prefs[modelUrl].takeIf { pending && prefs[useCustomModel] == true }
        val presetId = migrate(url, prefs[mmprojUrl])
        context.advancedSettingsPreferences.edit { prefs ->
            if (pending && prefs[Keys.modelId] == null) {
                prefs[Keys.modelId] = presetId.orEmpty()
            }
            prefs.remove(useCustomModel)
            prefs.remove(modelUrl)
            prefs.remove(mmprojUrl)
        }
    }

    suspend fun unlockAdvancedSettings() {
        context.advancedSettingsPreferences.edit { prefs ->
            prefs[Keys.advancedUnlocked] = true
        }
    }

    fun persistUnlockAdvancedSettings() {
        persistenceScope.launch {
            unlockAdvancedSettings()
        }
    }

    suspend fun saveSystemPrompt(value: String) {
        context.advancedSettingsPreferences.edit { prefs ->
            prefs[Keys.systemPrompt] = value
        }
    }

    fun persistSystemPrompt(value: String) {
        persistenceScope.launch {
            saveSystemPrompt(value)
        }
    }

    suspend fun saveModelSettings(settings: ModelSettingsState) {
        context.advancedSettingsPreferences.edit { prefs ->
            prefs[Keys.modelId] = settings.modelId
            prefs[Keys.contextLength] = settings.contextLength
            prefs[Keys.maxTokens] = settings.maxTokens
            prefs[Keys.temperature] = settings.temperature
        }
    }

    fun persistModelSettings(settings: ModelSettingsState) {
        persistenceScope.launch {
            saveModelSettings(settings)
        }
    }

    suspend fun resetModelSettings() {
        context.advancedSettingsPreferences.edit { prefs ->
            prefs[Keys.modelId] = ""
            prefs[Keys.contextLength] = ""
            prefs[Keys.maxTokens] = ""
            prefs[Keys.temperature] = ""
        }
    }

    fun persistResetModelSettings() {
        persistenceScope.launch {
            resetModelSettings()
        }
    }

    companion object {
        private object Keys {
            val advancedUnlocked = booleanPreferencesKey("advanced_unlocked")
            val systemPrompt = stringPreferencesKey("system_prompt")
            val modelId = stringPreferencesKey("model_id")
            val contextLength = stringPreferencesKey("context_length")
            val maxTokens = stringPreferencesKey("max_tokens")
            val temperature = stringPreferencesKey("temperature")
        }
    }
}
