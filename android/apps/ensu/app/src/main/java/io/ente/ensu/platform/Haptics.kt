package io.ente.ensu.platform

import android.content.Context
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView

class Haptics(
    private val context: Context,
    private val view: View,
) {
    fun perform(type: HapticFeedbackType) {
        val feedback = mapToHapticConstant(type)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            if (!view.performHapticFeedback(feedback)) {
                view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
            }
            return
        }

        if (!shouldForceVibrationFallback() && view.performHapticFeedback(feedback)) return

        val vibrator =
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator ?: return
        val effect =
            when (type) {
                HapticFeedbackType.LongPress -> VibrationEffect.EFFECT_HEAVY_CLICK
                else -> VibrationEffect.EFFECT_TICK
            }
        vibrator.vibrate(
            VibrationEffect.createPredefined(effect),
            VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH),
        )
    }

    private fun shouldForceVibrationFallback(): Boolean {
        val manufacturer = Build.MANUFACTURER?.lowercase().orEmpty()
        val brand = Build.BRAND?.lowercase().orEmpty()
        return manufacturer.contains("nothing") || brand.contains("nothing")
    }

    private fun mapToHapticConstant(type: HapticFeedbackType): Int {
        return when (type) {
            HapticFeedbackType.LongPress -> HapticFeedbackConstants.LONG_PRESS
            HapticFeedbackType.TextHandleMove -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    HapticFeedbackConstants.TEXT_HANDLE_MOVE
                } else {
                    HapticFeedbackConstants.KEYBOARD_TAP
                }
            }
            else -> HapticFeedbackConstants.KEYBOARD_TAP
        }
    }
}

@Composable
fun rememberHaptics(): Haptics {
    val context = LocalContext.current
    val view = LocalView.current
    return remember(context, view) { Haptics(context, view) }
}
