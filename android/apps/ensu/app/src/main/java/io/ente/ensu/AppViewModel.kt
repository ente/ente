package io.ente.ensu

import android.app.Application
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.pm.PackageInfoCompat
import androidx.lifecycle.AndroidViewModel
import io.ente.ensu.logging.LogLevel

class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val runtime = (application as EnsuApplication).runtime
    val store = runtime.store
    val isReady = runtime.isReady
    val advancedSettingsDataStore = runtime.advancedSettingsDataStore
    val appVersion = runCatching { getAppVersion(application) }.getOrDefault("unknown")
    val configDefaults = runtime.configDefaults
    val logRepository = runtime.logRepository

    init {
        val launchMessage =
            "App launched app=$appVersion device=${Build.MANUFACTURER} ${Build.MODEL} os=${Build.VERSION.RELEASE} (sdk=${Build.VERSION.SDK_INT})"
        logRepository.log(LogLevel.Info, launchMessage, tag = "App")
    }

    override fun onCleared() {
        store.voiceController.discard()
        super.onCleared()
    }

    private fun getAppVersion(application: Application): String {
        val packageManager = application.packageManager
        val packageName = application.packageName
        val packageInfo =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION") packageManager.getPackageInfo(packageName, 0)
            }
        val versionName = packageInfo.versionName ?: "unknown"
        val versionCode = PackageInfoCompat.getLongVersionCode(packageInfo)
        return "$versionName+$versionCode"
    }
}
