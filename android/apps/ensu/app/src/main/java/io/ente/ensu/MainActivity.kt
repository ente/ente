package io.ente.ensu

import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.lifecycle.viewmodel.compose.viewModel
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.Theme
import io.ente.ensu.notifications.BackgroundGeneration
import io.ente.ensu.notifications.NotificationPermissionPrompt

class MainActivity : ComponentActivity() {
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        openResponse(intent)
    }

    private fun openResponse(intent: Intent) {
        val session = intent.getStringExtra(BackgroundGeneration.SESSION) ?: return
        (application as EnsuApplication)
            .runtime
            .openNotification(session, intent.getStringExtra(BackgroundGeneration.MESSAGE))
        intent.removeExtra(BackgroundGeneration.SESSION)
        intent.removeExtra(BackgroundGeneration.MESSAGE)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        openResponse(intent)
        enableEdgeToEdge(
            navigationBarStyle =
                SystemBarStyle.auto(
                    EnsuColor.backgroundBaseLight.toArgb(),
                    EnsuColor.backgroundBaseDark.toArgb(),
                )
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
        setContent {
            Theme {
                val appViewModel: AppViewModel = viewModel()
                Box(
                    modifier =
                        Modifier.fillMaxSize()
                            .background(EnsuColor.backgroundBase())
                            .safeDrawingPadding()
                ) {
                    App(appViewModel = appViewModel)
                    NotificationPermissionPrompt(
                        this@MainActivity,
                        (application as EnsuApplication).notificationPermissions,
                    )
                }
            }
        }
    }
}
