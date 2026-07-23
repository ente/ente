package io.ente.ensu.settings

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuCornerRadius
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.designsystem.HugeIcons

internal const val IS_ENSU_PACKS_ENABLED = false

@Composable
fun SettingsScreen(
    buildVersion: String,
    isAdvancedUnlocked: Boolean,
    onOpenLogs: () -> Unit,
    onOpenKnowledge: () -> Unit,
    onOpenModelSettings: () -> Unit,
    onOpenSystemPromptSettings: () -> Unit,
    onUnlockAdvanced: () -> Unit,
    onSignIn: () -> Unit
) {
    var query by remember { mutableStateOf("") }
    var buildVersionTapCount by remember { mutableStateOf(0) }
    var lastBuildVersionTapAt by remember { mutableStateOf<Long?>(null) }
    val context = LocalContext.current

    val allItems = remember(context, onOpenLogs, onOpenKnowledge, onSignIn) {
        buildList {
            add(
                SettingsItem(
                    title = "About",
                    iconVector = Icons.Outlined.Info,
                    onClick = { context.openExternalLink("https://ente.com/blog/ensu/") }
                )
            )

            if (IS_ENSU_PACKS_ENABLED) {
                add(
                    SettingsItem(
                        title = "Ensu Packs",
                        iconRes = HugeIcons.PackageIcon,
                        onClick = onOpenKnowledge
                    )
                )
            }

            add(
                SettingsItem(
                    title = "Logs",
                    iconRes = HugeIcons.Bug01Icon,
                    onClick = onOpenLogs
                )
            )

            add(
                SettingsItem(
                    title = "Sign In to Backup",
                    iconRes = HugeIcons.Upload01Icon,
                    onClick = onSignIn
                )
            )

            add(
                SettingsItem(
                    title = "Privacy Policy",
                    iconRes = HugeIcons.ViewIcon,
                    onClick = { context.openExternalLink("https://ente.com/privacy") }
                )
            )
            add(
                SettingsItem(
                    title = "Terms of Service",
                    iconVector = Icons.Outlined.Description,
                    onClick = { context.openExternalLink("https://ente.com/terms") }
                )
            )
        }
    }

    val filteredItems = remember(query, allItems) {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return@remember allItems
        allItems.filter { item ->
            item.title.lowercase().contains(q)
        }
    }

    fun handleBuildVersionTap() {
        if (isAdvancedUnlocked) return
        val now = System.currentTimeMillis()
        val lastTap = lastBuildVersionTapAt
        if (lastTap != null && now - lastTap > 2000) {
            buildVersionTapCount = 0
        }
        lastBuildVersionTapAt = now
        buildVersionTapCount += 1
        if (buildVersionTapCount >= 5) {
            buildVersionTapCount = 0
            onUnlockAdvanced()
            Toast.makeText(context, "Advanced settings unlocked", Toast.LENGTH_SHORT).show()
        }
    }

    Column(modifier = Modifier.padding(EnsuSpacing.pageHorizontal.dp)) {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text(text = "Search settings", style = EnsuTypography.body) },
            singleLine = true,
            colors = TextFieldDefaults.colors(
                focusedContainerColor = EnsuColor.fillFaint(),
                unfocusedContainerColor = EnsuColor.fillFaint(),
                focusedIndicatorColor = EnsuColor.fillFaint(),
                unfocusedIndicatorColor = EnsuColor.fillFaint()
            ),
            shape = RoundedCornerShape(EnsuCornerRadius.input.dp)
        )

        Spacer(modifier = Modifier.size(EnsuSpacing.lg.dp))

        LazyColumn(verticalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp)) {
            items(filteredItems, key = { it.title }) { item ->
                SettingsRow(item)
            }

            if (isAdvancedUnlocked && query.isBlank()) {
                item(key = "advanced-header") {
                    Spacer(modifier = Modifier.size(EnsuSpacing.sm.dp))
                    Text(
                        text = "Advanced",
                        style = EnsuTypography.small,
                        color = EnsuColor.textMuted(),
                        modifier = Modifier.padding(vertical = EnsuSpacing.xs.dp)
                    )
                }
                item(key = "advanced-model-settings") {
                    SettingsRow(
                        SettingsItem(
                            title = "Model settings",
                            iconRes = HugeIcons.Settings01Icon,
                            onClick = onOpenModelSettings
                        )
                    )
                }
                item(key = "advanced-system-prompt") {
                    SettingsRow(
                        SettingsItem(
                            title = "System prompt",
                            iconRes = HugeIcons.Edit01Icon,
                            onClick = onOpenSystemPromptSettings
                        )
                    )
                }
            }

            if (query.isBlank()) {
                item(key = "build-version") {
                    Spacer(modifier = Modifier.size(EnsuSpacing.sm.dp))
                    Text(
                        text = "Build version $buildVersion",
                        style = EnsuTypography.small,
                        color = EnsuColor.textMuted(),
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(onClick = ::handleBuildVersionTap)
                            .padding(vertical = EnsuSpacing.sm.dp)
                    )
                }
            }
        }
    }
}

private data class SettingsItem(
    val title: String,
    val iconRes: Int? = null,
    val iconVector: ImageVector? = null,
    val onClick: () -> Unit,
    val isDestructive: Boolean = false
)

@Composable
private fun SettingsRow(item: SettingsItem) {
    val iconAndTextColor = if (item.isDestructive) EnsuColor.error else EnsuColor.textPrimary()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EnsuCornerRadius.card.dp))
            .background(EnsuColor.fillFaint())
            .clickable(onClick = item.onClick)
            .padding(horizontal = EnsuSpacing.lg.dp, vertical = EnsuSpacing.lg.dp),
        horizontalArrangement = Arrangement.spacedBy(EnsuSpacing.md.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        item.iconVector?.let { iconVector ->
            Icon(
                imageVector = iconVector,
                contentDescription = null,
                tint = iconAndTextColor,
                modifier = Modifier.size(18.dp)
            )
        } ?: item.iconRes?.let { iconRes ->
            Icon(
                painter = painterResource(iconRes),
                contentDescription = null,
                tint = iconAndTextColor,
                modifier = Modifier.size(18.dp)
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(text = item.title, style = EnsuTypography.body, color = iconAndTextColor)
        }
        Icon(
            painter = painterResource(HugeIcons.ArrowRight01Icon),
            contentDescription = null,
            tint = EnsuColor.textMuted(),
            modifier = Modifier.size(18.dp)
        )
    }
}

private fun Context.openExternalLink(url: String) {
    runCatching {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        ContextCompat.startActivity(this, intent, null)
    }
}
