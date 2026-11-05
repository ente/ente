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
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import io.ente.ensu.components.CompactButton
import io.ente.ensu.components.KnowledgeCard
import io.ente.ensu.components.TextActionButton
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography

@OptIn(ExperimentalMaterial3Api::class)
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
        ModalBottomSheet(
            onDismissRequest = permissions::dismiss,
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = EnsuColor.backgroundBase(),
        ) {
            Column(
                Modifier.fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = EnsuSpacing.pageHorizontal.dp)
                    .padding(bottom = EnsuSpacing.lg.dp),
                verticalArrangement = Arrangement.spacedBy(EnsuSpacing.lg.dp),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp)) {
                    Text(
                        "Let Ensu notify you",
                        style = EnsuTypography.h3,
                        color = EnsuColor.textPrimary(),
                    )
                    Text(
                        "Switch to another app while Ensu works.",
                        style = EnsuTypography.body,
                        color = EnsuColor.textMuted(),
                    )
                }
                KnowledgeCard(spacing = EnsuSpacing.sm.dp) {
                    Text(
                        "Response notifications",
                        style = EnsuTypography.large,
                        color = EnsuColor.textPrimary(),
                    )
                    Text(
                        if (canRequest)
                            "We’ll let you know when your response is ready, with the answer in the notification."
                        else
                            "Turn on notifications in Settings to see when your response is ready, with the answer in the notification.",
                        style = EnsuTypography.small,
                        color = EnsuColor.textMuted(),
                    )
                    CompactButton(
                        label = if (canRequest) "Enable notifications" else "Open settings",
                        prominent = true,
                        onClick = {
                            permissions.dismiss()
                            if (canRequest) {
                                requestPermission = true
                            } else permissions.openSettings(activity)
                        },
                    )
                }
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(EnsuSpacing.xs.dp),
                ) {
                    TextActionButton(
                        text = "Not now",
                        onTap = permissions::dismiss,
                        underlined = true,
                        color = EnsuColor.textPrimary(),
                    )
                    Text(
                        "You can change notification preferences later from Settings.",
                        style = EnsuTypography.mini.copy(fontWeight = FontWeight.Normal),
                        color = EnsuColor.textMuted(),
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
}

private fun ComponentActivity.canShowNotificationPrompt(): Boolean {
    val keyguard = getSystemService(KeyguardManager::class.java)
    return lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) &&
        !keyguard.isDeviceLocked &&
        !keyguard.isKeyguardLocked
}
