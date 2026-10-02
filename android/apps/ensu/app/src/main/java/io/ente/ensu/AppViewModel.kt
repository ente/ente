package io.ente.ensu

import android.app.Application
import androidx.lifecycle.AndroidViewModel

class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val runtime = (application as EnsuApplication).runtime
    val store = runtime.store
    val isReady = runtime.isReady
    val advancedSettingsDataStore = runtime.advancedSettingsDataStore
    val appVersion = runtime.appVersion
    val configDefaults = runtime.configDefaults
    val logRepository = runtime.logRepository

    override fun onCleared() {
        store.voiceController.discard()
        super.onCleared()
    }
}
