package io.ente.ensu

import android.app.Application
import android.content.pm.PackageManager
import android.os.Build
import io.ente.ensu.chat.ChatRepository
import io.ente.ensu.config.loadConfigDefaults
import io.ente.ensu.coroutines.runCatchingCancellable
import io.ente.ensu.device.AndroidDeviceCapabilityProvider
import io.ente.ensu.llm.LlmProvider
import io.ente.ensu.logging.LogLevel
import io.ente.ensu.settings.AdvancedSettingsDataStore
import io.ente.ensu.settings.AdvancedSettingsSnapshot
import io.ente.ensu.settings.SessionPreferencesDataStore
import io.ente.ensu.storage.CredentialStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class AppRuntime(application: EnsuApplication) {
    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    fun openNotification(sessionId: String, messageId: String?) {
        applicationScope.launch {
            store.openNotification(sessionId, messageId) { isReady.first { it } }
        }
    }

    private val sessionPreferences = SessionPreferencesDataStore(application)
    val advancedSettingsDataStore = AdvancedSettingsDataStore(application)
    private val credentialStore = CredentialStore(application)
    val appVersion = runCatching { getAppVersion(application) }.getOrDefault("unknown")
    private val deviceCapabilityProvider = AndroidDeviceCapabilityProvider(application)
    private val transcriber = application.transcriber
    val configDefaults = loadConfigDefaults()

    val logRepository = application.logRepository
    private val assetStore = application.assetStore
    private val _isReady = MutableStateFlow(false)
    val isReady = _isReady.asStateFlow()
    private val llmProvider =
        LlmProvider(
            assetStore = assetStore,
            transcriber = transcriber,
            deviceCapabilityProvider = deviceCapabilityProvider,
            knowledgeEmbedding = configDefaults.knowledgeEmbedding,
            nativeLibraryDir = application.applicationInfo.nativeLibraryDir,
        )
    private val chatRepository = ChatRepository(application, credentialStore)
    private val knowledgeProvider = application.knowledgeProvider

    val store =
        AppStore(
            context = application,
            backgroundGeneration = application.backgroundGeneration,
            notificationPermissions = application.notificationPermissions,
            sessionPreferences = sessionPreferences,
            chatRepository = chatRepository,
            llmProvider = llmProvider,
            knowledgeProvider = knowledgeProvider,
            assetStore = assetStore,
            deviceCapabilityProvider = deviceCapabilityProvider,
            configDefaults = configDefaults,
            logRepository = logRepository,
        )

    init {
        val launchMessage =
            "App launched app=$appVersion device=${Build.MANUFACTURER} ${Build.MODEL} os=${Build.VERSION.RELEASE} (sdk=${Build.VERSION.SDK_INT})"
        logRepository.log(LogLevel.Info, launchMessage, tag = "App")

        applicationScope.launch {
            runCatchingCancellable {
                advancedSettingsDataStore.migrateLegacyModelSelection { url, mmproj ->
                    withContext(Dispatchers.IO) { assetStore.migrate(url, mmproj) }
                }
            }
            val initialSettings = runCatchingCancellable {
                advancedSettingsDataStore.settingsFlow.first()
            }
                .getOrDefault(AdvancedSettingsSnapshot())
            store.applyPersistedSettings(
                developerSettings = initialSettings.developerSettings,
                modelSettings = initialSettings.modelSettings,
            )
            store.hydrateModelDownloadRequested(
                runCatchingCancellable { sessionPreferences.modelDownloadRequested.first() }
                    .getOrDefault(false)
            )
            store.bootstrap(applicationScope)
            _isReady.value = true

            advancedSettingsDataStore.settingsFlow.drop(1).collectLatest { settings ->
                store.applyPersistedSettings(
                    developerSettings = settings.developerSettings,
                    modelSettings = settings.modelSettings,
                )
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun getAppVersion(application: Application): String {
        val packageManager = application.packageManager
        val packageName = application.packageName
        val packageInfo =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
            } else {
                packageManager.getPackageInfo(packageName, 0)
            }
        val versionName = packageInfo.versionName ?: "unknown"
        val versionCode =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode
            } else {
                packageInfo.versionCode.toLong()
            }
        return "$versionName+$versionCode"
    }
}
