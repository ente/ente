@file:OptIn(ExperimentalMaterial3Api::class)

package io.ente.ensu

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.ente.ensu.components.Logo
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.designsystem.HugeIcons

@Composable
internal fun TopBar(
    sessionTitle: String?,
    showBrand: Boolean,
    modelDownloadStatus: String?,
    modelDownloadPercent: Int?,
    onOpenDrawer: () -> Unit,
    onNewChat: () -> Unit
) {
    val titleText = sessionTitle?.takeIf { it.isNotBlank() } ?: "New Chat"

    CenterAlignedTopAppBar(
        title = {
            if (showBrand) {
                Logo(height = 23.dp)
            } else {
                Text(
                    text = titleText,
                    style = EnsuTypography.h3Bold.copy(fontSize = 20.sp, lineHeight = 24.sp),
                    color = EnsuColor.textPrimary(),
                    maxLines = 1
                )
            }
        },
        navigationIcon = {
            IconButton(onClick = onOpenDrawer) {
                Icon(
                    painter = painterResource(HugeIcons.Menu01Icon),
                    contentDescription = "Menu"
                )
            }
        },
        actions = {
            val isLoading = modelDownloadStatus?.contains("Loading", ignoreCase = true) == true
            val showModelProgress = isLoading

            if (showModelProgress) {
                ModelProgressIndicator(
                    isLoading = isLoading,
                    progressPercent = modelDownloadPercent
                )
            }

            if (showModelProgress) {
                Spacer(modifier = Modifier.width(EnsuSpacing.sm.dp))
            }

            IconButton(
                onClick = onNewChat,
                modifier = Modifier.padding(end = EnsuSpacing.sm.dp)
            ) {
                Icon(
                    painter = painterResource(HugeIcons.PlusSignIcon),
                    contentDescription = "New chat"
                )
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = EnsuColor.backgroundBase())
    )
}

@Composable
private fun ModelProgressIndicator(
    isLoading: Boolean,
    progressPercent: Int?,
    modifier: Modifier = Modifier
) {
    val indicatorModifier = modifier.size(16.dp)
    val clamped = progressPercent?.coerceIn(0, 100)
    if (!isLoading && clamped != null) {
        CircularProgressIndicator(
            progress = { clamped / 100f },
            modifier = indicatorModifier,
            color = EnsuColor.action(),
            trackColor = EnsuColor.border(),
            strokeWidth = 2.dp
        )
    } else {
        CircularProgressIndicator(
            modifier = indicatorModifier,
            color = EnsuColor.action(),
            trackColor = EnsuColor.border(),
            strokeWidth = 2.dp
        )
    }
}

@Composable
internal fun SimpleTopBar(title: String, onBack: () -> Unit) {
    TopAppBar(
        title = { Text(text = title, style = EnsuTypography.h3Bold.copy(fontSize = 20.sp, lineHeight = 24.sp)) },
        navigationIcon = {
            IconButton(onClick = onBack) {
                Icon(
                    painter = painterResource(HugeIcons.ArrowLeft01Icon),
                    contentDescription = "Back"
                )
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = EnsuColor.backgroundBase())
    )
}

@Composable
internal fun LogsTopBar(onBack: () -> Unit, onShare: () -> Unit) {
    TopAppBar(
        title = { Text(text = "Logs", style = EnsuTypography.h3Bold.copy(fontSize = 20.sp, lineHeight = 24.sp)) },
        navigationIcon = {
            IconButton(onClick = onBack) {
                Icon(
                    painter = painterResource(HugeIcons.ArrowLeft01Icon),
                    contentDescription = "Back"
                )
            }
        },
        actions = {
            IconButton(onClick = onShare) {
                Icon(
                    painter = painterResource(HugeIcons.Upload01Icon),
                    contentDescription = "Share",
                    modifier = Modifier.size(18.dp)
                )
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = EnsuColor.backgroundBase())
    )
}
