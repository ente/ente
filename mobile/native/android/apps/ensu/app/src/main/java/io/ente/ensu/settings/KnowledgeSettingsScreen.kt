package io.ente.ensu.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuCornerRadius
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.format.formatBytes
import io.ente.ensu.bindings.KnowledgeDatasetConfig
import io.ente.ensu.bindings.KnowledgeReconciliationStatus
import io.ente.ensu.knowledge.KnowledgePackState
import io.ente.ensu.knowledge.KnowledgeState

@Composable
fun KnowledgeSettingsScreen(
    state: KnowledgeState,
    packDownloadsAllowed: Boolean,
    onDownloadOrUpdate: (String) -> Unit,
    onCancel: (String) -> Unit,
    onSetEnabled: (String, Boolean) -> Unit
) {
    var attributionConfig by remember { mutableStateOf<KnowledgeDatasetConfig?>(null) }

    LazyColumn(
        modifier = Modifier.padding(horizontal = EnsuSpacing.pageHorizontal.dp),
        verticalArrangement = Arrangement.spacedBy(EnsuSpacing.md.dp)
    ) {
        items(state.packs.values.toList(), key = { it.config.stableId }) { pack ->
            KnowledgePackCard(
                pack = pack,
                packDownloadsAllowed = packDownloadsAllowed,
                onDownloadOrUpdate = { onDownloadOrUpdate(pack.config.stableId) },
                onCancel = { onCancel(pack.config.stableId) },
                onSetEnabled = { enabled -> onSetEnabled(pack.config.stableId, enabled) },
                onOpenAttribution = { attributionConfig = pack.config }
            )
        }
    }

    attributionConfig?.let { config ->
        PackAttributionDialog(
            config = config,
            onDismiss = { attributionConfig = null }
        )
    }
}

@Composable
private fun KnowledgePackCard(
    pack: KnowledgePackState,
    packDownloadsAllowed: Boolean,
    onDownloadOrUpdate: () -> Unit,
    onCancel: () -> Unit,
    onSetEnabled: (Boolean) -> Unit,
    onOpenAttribution: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                EnsuColor.fillFaint(),
                RoundedCornerShape(EnsuCornerRadius.card.dp)
            )
            .padding(EnsuSpacing.lg.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(EnsuSpacing.xs.dp)
            ) {
                Text(pack.config.label, style = EnsuTypography.large, color = EnsuColor.textPrimary())
                PackMetadataLine(pack = pack, onOpenAttribution = onOpenAttribution)
            }
            if (pack.activeIdentity != null && !pack.isMutating) {
                Switch(checked = pack.enabled, onCheckedChange = onSetEnabled)
            } else if (
                packDownloadsAllowed &&
                pack.status == KnowledgeReconciliationStatus.DOWNLOAD &&
                !pack.isMutating
            ) {
                CompactPackButton(label = "Download", onClick = onDownloadOrUpdate)
            }
        }

        if (pack.isMutating) {
            Spacer(Modifier.height(EnsuSpacing.md.dp))
            LinearProgressIndicator(
                progress = { (pack.mutationProgress?.percentage ?: 0.0).coerceIn(0.0, 100.0).toFloat() / 100f },
                modifier = Modifier.fillMaxWidth(),
                color = EnsuColor.accent(),
                trackColor = EnsuColor.border()
            )
            Text(
                pack.mutationProgress?.label ?: "Downloading...",
                style = EnsuTypography.small,
                color = EnsuColor.textMuted()
            )
            TextButton(onClick = onCancel) { Text("Cancel") }
        } else if (
            packDownloadsAllowed &&
            pack.status == KnowledgeReconciliationStatus.UPDATE_AVAILABLE
        ) {
            Spacer(Modifier.height(EnsuSpacing.md.dp))
            CompactPackButton(label = "Update", onClick = onDownloadOrUpdate)
        }

        pack.errorMessage?.let {
            Text(it, style = EnsuTypography.small, color = EnsuColor.error)
        }
    }
}

@Composable
private fun PackMetadataLine(
    pack: KnowledgePackState,
    onOpenAttribution: () -> Unit
) {
    val attribution = pack.config.attribution
    Row(
        horizontalArrangement = Arrangement.spacedBy(EnsuSpacing.xs.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = formatBytes(pack.config.downloadSizeBytes),
            style = EnsuTypography.mini,
            color = EnsuColor.textMuted()
        )
        Text("·", style = EnsuTypography.mini, color = EnsuColor.textMuted())
        Row(
            modifier = Modifier.clickable(onClick = onOpenAttribution),
            horizontalArrangement = Arrangement.spacedBy(EnsuSpacing.xs.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = attribution.licenseLabel,
                style = EnsuTypography.mini,
                color = EnsuColor.accent()
            )
            Icon(
                imageVector = Icons.Outlined.Info,
                contentDescription = "View attribution for ${pack.config.label}",
                tint = EnsuColor.accent(),
                modifier = Modifier.size(14.dp)
            )
        }
    }
}

@Composable
private fun CompactPackButton(label: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(containerColor = EnsuColor.accent()),
        contentPadding = PaddingValues(
            horizontal = EnsuSpacing.md.dp,
            vertical = EnsuSpacing.xs.dp
        )
    ) {
        Text(label, style = EnsuTypography.mini)
    }
}

@Composable
private fun PackAttributionDialog(
    config: KnowledgeDatasetConfig,
    onDismiss: () -> Unit
) {
    val attribution = config.attribution
    val uriHandler = LocalUriHandler.current

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Attribution", style = EnsuTypography.h3) },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        EnsuColor.fillFaint(),
                        RoundedCornerShape(EnsuCornerRadius.card.dp)
                    )
                    .padding(EnsuSpacing.md.dp),
                verticalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp)
            ) {
                Text(
                    text = config.label,
                    style = EnsuTypography.large,
                    color = EnsuColor.textPrimary()
                )
                HorizontalDivider(color = EnsuColor.border())
                Text(
                    text = "From ${attribution.credit}",
                    style = EnsuTypography.small,
                    color = EnsuColor.textPrimary()
                )
                Text(
                    text = attribution.modificationNotice,
                    style = EnsuTypography.small,
                    color = EnsuColor.textPrimary()
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(EnsuSpacing.md.dp)
                ) {
                    AttributionLink("Source ↗") {
                        uriHandler.openUri(attribution.publicPackUrl)
                    }
                    AttributionLink("License ↗") {
                        uriHandler.openUri(attribution.licenseUrl)
                    }
                }
                HorizontalDivider(color = EnsuColor.border())
                Text(
                    text = "Wikimedia and Ensu are not affiliated. Wikimedia project names identify the source material only.",
                    style = EnsuTypography.small,
                    color = EnsuColor.textMuted()
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Done") }
        },
        containerColor = EnsuColor.backgroundBase()
    )
}

@Composable
private fun AttributionLink(label: String, onClick: () -> Unit) {
    Text(
        text = label,
        style = EnsuTypography.mini,
        color = EnsuColor.accent(),
        maxLines = 1,
        modifier = Modifier
            .clickable(onClick = onClick)
            .padding(vertical = EnsuSpacing.xs.dp)
    )
}
