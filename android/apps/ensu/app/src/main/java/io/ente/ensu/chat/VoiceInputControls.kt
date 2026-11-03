package io.ente.ensu.chat

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import io.ente.ensu.bindings.DictationPhase
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.designsystem.HugeIcons
import io.ente.ensu.platform.rememberHaptics

@Composable
internal fun VoiceInputControls(controller: VoiceTranscriptionController) {
    val state = controller.state
    if (!controller.active && state !is VoiceInputState.Error) return
    val permissionNeeded = (state as? VoiceInputState.Error)?.reason == VoiceInputFailure.Permission
    val context = LocalContext.current
    val label =
        when (state) {
            is VoiceInputState.Downloading -> if (state.queued) "Download queued" else "Downloading"
            VoiceInputState.Preparing,
            VoiceInputState.Idle -> "Preparing"
            VoiceInputState.Transcribing ->
                if (controller.isFinishingSlow) "Still transcribing" else "Transcribing"
            VoiceInputState.Recording ->
                if (controller.snapshot?.phase == DictationPhase.COUNTDOWN) "Finishing"
                else "Listening"
            is VoiceInputState.Error -> state.reason.message
        }
    Row(
        Modifier.padding(horizontal = EnsuSpacing.pageHorizontal.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            label,
            style = EnsuTypography.small,
            color = EnsuColor.textMuted(),
            modifier =
                Modifier.semantics { liveRegion = LiveRegionMode.Polite }
                    .then(
                        if (permissionNeeded)
                            Modifier.clickable(onClickLabel = "Enable microphone") {
                                context.startActivity(
                                    Intent(
                                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                        Uri.parse("package:${context.packageName}"),
                                    )
                                )
                            }
                        else Modifier
                    ),
        )
        if (state.isRecording)
            VoiceWaveform(controller.audioLevels, Modifier.weight(1f).height(24.dp))
        else Spacer(Modifier.weight(1f))
        if (controller.active && !state.isRecording) {
            TextButton(onClick = { controller.discard() }) { Text("Cancel") }
        }
    }
}

@Composable
internal fun VoiceInputButton(
    controller: VoiceTranscriptionController,
    enabled: Boolean,
    onOpen: () -> Unit,
) {
    val context = LocalContext.current
    val haptic = rememberHaptics()
    var permissionRequest by rememberSaveable { mutableStateOf<Long?>(null) }
    val permission =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
            if (controller.active && permissionRequest == controller.sessionVersion)
                controller.permissionResult(it)
            permissionRequest = null
        }
    fun record() {
        if (
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
        )
            controller.record()
        else {
            permissionRequest = controller.sessionVersion
            controller.permissionRequested()
            permission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
    LaunchedEffect(controller.active, controller.sessionVersion) {
        if (controller.active && controller.takeInitialRecord()) record()
    }
    val state = controller.state
    val downloading = state as? VoiceInputState.Downloading
    val preparing = state == VoiceInputState.Preparing
    val transcribing = state == VoiceInputState.Transcribing
    val capturing = state.isRecording
    val canPress = if (controller.active) capturing else enabled && controller.canOpen
    val description =
        when {
            downloading?.queued == true -> "Voice model download queued"
            downloading != null -> "Downloading voice model"
            preparing -> "Preparing voice input"
            transcribing -> "Transcribing"
            capturing -> "Stop dictation"
            else -> "Dictate"
        }
    IconButton(
        onClick = {
            when {
                capturing -> {
                    haptic.perform(HapticFeedbackType.LongPress)
                    controller.stop()
                }
                else -> onOpen()
            }
        },
        enabled = canPress,
        modifier = Modifier.size(36.dp).semantics { contentDescription = description },
    ) {
        when {
            downloading != null || preparing || transcribing ->
                Box(Modifier.size(28.dp), contentAlignment = Alignment.Center) {
                    if (downloading?.percent != null && !downloading.queued)
                        CircularProgressIndicator(
                            progress = { downloading.percent.coerceIn(0, 100) / 100f },
                            modifier = Modifier.size(28.dp),
                            strokeWidth = 2.dp,
                            color = EnsuColor.textPrimary(),
                        )
                    else
                        CircularProgressIndicator(
                            Modifier.size(28.dp),
                            strokeWidth = 2.dp,
                            color = EnsuColor.textPrimary(),
                        )
                    if (downloading != null)
                        Icon(Icons.Rounded.ArrowDownward, null, Modifier.size(14.dp))
                }
            capturing ->
                Box(
                    Modifier.size(32.dp).background(EnsuColor.textPrimary(), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        painterResource(HugeIcons.StopIcon),
                        null,
                        Modifier.size(14.dp),
                        tint = EnsuColor.backgroundBase(),
                    )
                }
            else -> Icon(painterResource(HugeIcons.Mic02Icon), null, Modifier.size(18.dp))
        }
    }
}

@Composable
private fun VoiceWaveform(levels: List<Float>, modifier: Modifier) {
    val animated = levels.map {
        animateFloatAsState(it, tween(100), label = "Microphone level").value
    }
    val color = EnsuColor.textPrimary()
    Canvas(modifier.semantics { contentDescription = "Microphone activity" }) {
        val step = size.width / levels.size
        val width = minOf(3.dp.toPx(), step * 0.6f)
        animated.forEachIndexed { index, level ->
            val height = 3.dp.toPx() + (size.height - 3.dp.toPx()) * level
            drawRoundRect(
                color.copy(alpha = 0.35f + level * 0.65f),
                Offset(step * index + (step - width) / 2, (size.height - height) / 2),
                Size(width, height),
                CornerRadius(width / 2),
            )
        }
    }
}
