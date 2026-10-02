package io.ente.ensu.notifications

import android.Manifest
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import io.ente.ensu.components.PrimaryButton
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuTypography

@Composable
fun NotificationPermissionPrompt(
    activity: ComponentActivity,
    permissions: NotificationPermissions,
) {
    val prompt by permissions.prompt.collectAsState()
    var ready by remember(activity) { mutableStateOf(activity.canShowNotificationPrompt()) }
    var requestPermission by rememberSaveable { mutableStateOf(false) }
    DisposableEffect(activity, permissions) {
        val refresh = {
            ready = activity.canShowNotificationPrompt()
            if (ready) permissions.refresh()
        }
        val observer = LifecycleEventObserver { _, _ -> refresh() }
        val receiver =
            object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) = refresh()
            }
        activity.lifecycle.addObserver(observer)
        ContextCompat.registerReceiver(
            activity,
            receiver,
            IntentFilter(Intent.ACTION_USER_PRESENT).apply { addAction(Intent.ACTION_SCREEN_OFF) },
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        refresh()
        onDispose {
            activity.lifecycle.removeObserver(observer)
            activity.unregisterReceiver(receiver)
        }
    }
    val launcher =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
            permissions.requestFinished(activity)
        }
    LaunchedEffect(requestPermission, ready) {
        if (
            requestPermission &&
                ready &&
                activity.canShowNotificationPrompt() &&
                Build.VERSION.SDK_INT >= 33
        ) {
            requestPermission = false
            permissions.requestStarted(activity)
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    val current = prompt
    if (current != null && ready) {
        val canRequest = permissions.canRequest(activity)
        LaunchedEffect(current) { permissions.didShow(current) }
        AlertDialog(
            onDismissRequest = permissions::dismiss,
            title = {
                Text(
                    "Let Ensu notify you",
                    style = EnsuTypography.h3Bold,
                    color = EnsuColor.textPrimary(),
                )
            },
            containerColor = EnsuColor.backgroundBase(),
            tonalElevation = 0.dp,
            text = {
                Text(
                    if (canRequest)
                        "Switch to another app while Ensu works. We’ll let you know when your response is ready."
                    else
                        "Switch to another app while Ensu works. Turn on notifications in Settings, and we’ll let you know when your response is ready.",
                    style = EnsuTypography.body,
                    color = EnsuColor.textPrimary(),
                )
            },
            confirmButton = {
                Column(modifier = Modifier.fillMaxWidth()) {
                    PrimaryButton(
                        text = if (canRequest) "Enable notifications" else "Open settings",
                        isLoading = false,
                        isEnabled = true,
                        onClick = {
                            permissions.dismiss()
                            if (canRequest) {
                                requestPermission = true
                            } else permissions.openSettings(activity)
                        },
                    )
                    TextButton(onClick = permissions::dismiss, modifier = Modifier.fillMaxWidth()) {
                        Text(
                            "Not now",
                            style = EnsuTypography.body,
                            color = EnsuColor.textPrimary(),
                        )
                    }
                }
            },
        )
    }
}

private fun ComponentActivity.canShowNotificationPrompt(): Boolean {
    val keyguard = getSystemService(KeyguardManager::class.java)
    return lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) &&
        !keyguard.isDeviceLocked &&
        !keyguard.isKeyguardLocked
}
