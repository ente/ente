package io.ente.ensu

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.ente.ensu.designsystem.EnsuColor

@Composable
fun App(appViewModel: AppViewModel) {
    val appState by appViewModel.store.state.collectAsState()
    val isReady by appViewModel.isReady.collectAsState()
    if (!isReady) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(EnsuColor.backgroundBase()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            CircularProgressIndicator(color = EnsuColor.action())
            Spacer(Modifier.height(16.dp))
            Text("Preparing...", color = EnsuColor.textMuted())
        }
        return
    }
    RootView(
        appState = appState,
        store = appViewModel.store,
        logRepository = appViewModel.logRepository,
        advancedSettingsDataStore = appViewModel.advancedSettingsDataStore,
        appVersion = appViewModel.appVersion,
        configDefaults = appViewModel.configDefaults
    )
}
