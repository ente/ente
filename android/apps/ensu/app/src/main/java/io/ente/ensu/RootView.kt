package io.ente.ensu

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import io.ente.ensu.settings.AdvancedSettingsDataStore
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.bindings.ConfigDefaults
import io.ente.ensu.AppState
import io.ente.ensu.AppStore

@Composable
fun RootView(
    appState: AppState,
    store: AppStore,
    logRepository: FileLogRepository,
    advancedSettingsDataStore: AdvancedSettingsDataStore,
    appVersion: String,
    configDefaults: ConfigDefaults
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(EnsuColor.backgroundBase())
    ) {
        HomeView(
            appState = appState,
            store = store,
            logRepository = logRepository,
            advancedSettingsDataStore = advancedSettingsDataStore,
            appVersion = appVersion,
            configDefaults = configDefaults
        )
    }
}
