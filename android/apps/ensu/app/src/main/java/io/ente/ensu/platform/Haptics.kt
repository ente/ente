package io.ente.ensu.platform

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView

class Haptics(
    private val context: Context,
    private val view: View?
) {
    fun perform(type: HapticFeedbackType) {
        if (!isHapticsEnabled(context)) return

        if (shouldForceVibrationFallback()) {
            vibrate(type)
            return
        }

        val performed = view?.performHapticFeedback(mapToHapticConstant(type)) ?: false
        if (!performed) {
            vibrate(type)
        }
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

    private fun vibrate(type: HapticFeedbackType) {
        val vibrator = getVibrator() ?: return
        if (!vibrator.hasVibrator()) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val effect = when (type) {
                HapticFeedbackType.LongPress -> VibrationEffect.EFFECT_HEAVY_CLICK
                HapticFeedbackType.TextHandleMove -> VibrationEffect.EFFECT_TICK
                else -> VibrationEffect.EFFECT_TICK
            }
            vibrator.vibrate(VibrationEffect.createPredefined(effect))
            return
        }

        val (duration, amplitude) = when (type) {
            HapticFeedbackType.LongPress -> 40L to 180
            HapticFeedbackType.TextHandleMove -> 10L to 60
            else -> 10L to 60
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(duration, amplitude))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(duration)
        }
    }

    private fun getVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(VibratorManager::class.java)
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun isHapticsEnabled(context: Context): Boolean {
        return try {
            Settings.System.getInt(context.contentResolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) == 1
        } catch (_: Throwable) {
            true
        }
    }
}

@Composable
fun rememberHaptics(): Haptics {
    val context = LocalContext.current
    val view = LocalView.current
    return remember(context, view) {
        Haptics(context, view)
    }
}
