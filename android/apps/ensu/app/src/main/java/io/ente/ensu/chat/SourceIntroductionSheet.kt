package io.ente.ensu.chat

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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.ente.ensu.components.CompactButton
import io.ente.ensu.components.KnowledgeCard
import io.ente.ensu.components.TextActionButton
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SourceIntroductionSheet(
    onDismiss: () -> Unit,
    onOpenPacks: () -> Unit,
    onOpenNotes: () -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
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
                    "Give Ensu more context",
                    style = EnsuTypography.h3,
                    color = EnsuColor.textPrimary(),
                )
                Text(
                    "Add a knowledge pack or your notes to help Ensu answer accurately.",
                    style = EnsuTypography.body,
                    color = EnsuColor.textMuted(),
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(EnsuSpacing.md.dp)) {
                KnowledgeCard(spacing = EnsuSpacing.sm.dp) {
                    Text(
                        "Ensu Packs",
                        style = EnsuTypography.large,
                        color = EnsuColor.textPrimary(),
                    )
                    Text(
                        "Knowledge from Wikipedia to help Ensu get factual questions right.",
                        style = EnsuTypography.small,
                        color = EnsuColor.textMuted(),
                    )
                    CompactButton("Set up", onClick = onOpenPacks, prominent = true)
                }
                KnowledgeCard(spacing = EnsuSpacing.sm.dp) {
                    Text(
                        "Your Notes",
                        style = EnsuTypography.large,
                        color = EnsuColor.textPrimary(),
                    )
                    Text(
                        "Use a local Markdown notes folder to chat with your own knowledge base.",
                        style = EnsuTypography.small,
                        color = EnsuColor.textMuted(),
                    )
                    CompactButton("Set up", onClick = onOpenNotes, prominent = true)
                }
            }
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(EnsuSpacing.xs.dp),
            ) {
                TextActionButton(
                    text = "Not now",
                    onTap = onDismiss,
                    underlined = true,
                    color = EnsuColor.textPrimary(),
                )
                Text(
                    "You can set up Ensu Packs and Your Notes later from Settings.",
                    style = EnsuTypography.mini.copy(fontWeight = FontWeight.Normal),
                    color = EnsuColor.textMuted(),
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}
