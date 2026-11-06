package io.ente.ensu.notifications

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.ente.ensu.EnsuApplication
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

class NotificationPermissions(private val app: EnsuApplication) {
    private val preferences = app.getSharedPreferences("response_notifications", 0)
    private val requestState =
        NotificationPermissionRequestState(preferences.getBoolean("denialObserved", false))
    private val _prompt = MutableStateFlow<Prompt?>(null)
    val prompt = _prompt.asStateFlow()

    class Prompt {
        var counted = false
    }

    fun enabled(): Boolean {
        if (!NotificationManagerCompat.from(app).areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= 26) {
            val channel =
                app.getSystemService(NotificationManager::class.java)
                    .getNotificationChannel(BackgroundGeneration.RESPONSE_CHANNEL)
            if (channel?.importance == NotificationManager.IMPORTANCE_NONE) return false
        }
        return true
    }

    fun refresh() {
        if (enabled()) {
            preferences.edit().putBoolean("finished", true).apply()
            dismiss()
        }
    }

    fun onSend() {
        refresh()
        if (!app.backgroundGeneration.isForeground || _prompt.value != null) return
        val last =
            if (preferences.contains("lastShown")) preferences.getLong("lastShown", 0) else null
        if (
            canEducate(
                enabled(),
                preferences.getBoolean("finished", false),
                preferences.getInt("count", 0),
                last,
                System.currentTimeMillis(),
            )
        ) {
            _prompt.value = Prompt()
        }
    }

    fun didShow(prompt: Prompt) {
        if (prompt !== _prompt.value || prompt.counted) return
        prompt.counted = true
        preferences
            .edit()
            .putInt("count", preferences.getInt("count", 0) + 1)
            .putLong("lastShown", System.currentTimeMillis())
            .apply()
    }

    fun canRequest(activity: Activity): Boolean =
        Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(app, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED &&
            requestState.canRequest(shouldShowRationale(activity))

    fun requestStarted(activity: Activity) = observeDenial(activity)

    fun requestFinished(activity: Activity) {
        observeDenial(activity)
        refresh()
    }

    private fun shouldShowRationale(activity: Activity): Boolean =
        Build.VERSION.SDK_INT >= 33 &&
            ActivityCompat.shouldShowRequestPermissionRationale(
                activity,
                Manifest.permission.POST_NOTIFICATIONS,
            )

    private fun observeDenial(activity: Activity) {
        requestState.observeRationale(shouldShowRationale(activity))
        preferences.edit().putBoolean("denialObserved", requestState.denialObserved).apply()
    }

    fun dismiss() {
        _prompt.value = null
    }

    fun openSettings(context: Context) {
        val intent =
            if (
                Build.VERSION.SDK_INT >= 26 &&
                    !NotificationManagerCompat.from(app).areNotificationsEnabled()
            ) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, app.packageName)
            } else if (Build.VERSION.SDK_INT >= 26) {
                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, app.packageName)
                    .putExtra(Settings.EXTRA_CHANNEL_ID, BackgroundGeneration.RESPONSE_CHANNEL)
            } else {
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:${app.packageName}"),
                )
            }
        context.startActivity(intent)
    }
}
