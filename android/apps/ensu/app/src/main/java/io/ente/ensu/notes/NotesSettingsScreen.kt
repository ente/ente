package io.ente.ensu.notes

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import io.ente.ensu.components.KnowledgeCard
import io.ente.ensu.components.CompactButton
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.designsystem.HugeIcons
import java.text.DateFormat
import java.util.Date

@Composable
fun NotesSettingsScreen(store: NotesStore) {
    val state by store.state.collectAsState()
    var removing by remember { mutableStateOf<NoteCollectionState?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        uri?.let(store::add)
    }
    LazyColumn(
        modifier = Modifier.padding(horizontal = EnsuSpacing.pageHorizontal.dp),
        verticalArrangement = Arrangement.spacedBy(EnsuSpacing.md.dp)
    ) {
        items(state.collections, key = { it.id }) { collection ->
            KnowledgeCard(spacing = EnsuSpacing.sm.dp) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(EnsuSpacing.xs.dp)
                    ) {
                        Text(collection.label, style = EnsuTypography.large, color = EnsuColor.textPrimary())
                        Text(
                            text = buildString {
                                if (collection.documentCount == 0L && (collection.status == NotesStatus.Pending || collection.status == NotesStatus.Indexing)) {
                                    append("Preparing notes…")
                                } else {
                                    append("${collection.documentCount} ${if (collection.documentCount == 1L) "note indexed" else "notes indexed"}")
                                }
                                collection.lastUpdatedAtMs?.let {
                                    append(" · Updated at ")
                                    append(DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(it)))
                                }
                            },
                            style = EnsuTypography.mini,
                            color = EnsuColor.textMuted()
                        )
                    }
                    IconButton(onClick = { removing = collection }, modifier = Modifier.size(48.dp)) {
                        Icon(
                            painter = painterResource(HugeIcons.Delete01Icon),
                            contentDescription = "Remove ${collection.label}",
                            modifier = Modifier.size(18.dp),
                            tint = EnsuColor.textMuted()
                        )
                    }
                }
                collection.progress?.let { progress ->
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        LinearProgressIndicator(
                            progress = { progress.coerceIn(0, 100) / 100f },
                            modifier = Modifier.weight(1f),
                            color = EnsuColor.action(),
                            trackColor = EnsuColor.border()
                        )
                        Text("$progress%", style = EnsuTypography.mini, color = EnsuColor.textMuted())
                    }
                }
                if (collection.status == NotesStatus.Pending) {
                    Text(
                        "Indexing will continue when the app and model are ready.",
                        style = EnsuTypography.small,
                        color = EnsuColor.textMuted()
                    )
                }
                collection.error?.let {
                    Text(it, style = EnsuTypography.small, color = EnsuColor.error)
                    CompactButton(label = "Retry", onClick = { store.retry(collection.id) })
                }
            }
        }
        item {
            CompactButton(
                label = "Add notes folder",
                onClick = { picker.launch(null) }
            )
        }
        item {
            Text(
                "Ensu reads and indexes markdown files in the selected folder. Source files are never modified.",
                style = EnsuTypography.small,
                color = EnsuColor.textMuted()
            )
        }
        state.error?.let { error ->
            item { Text(error, style = EnsuTypography.small, color = EnsuColor.error) }
        }
    }
    removing?.let { collection ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text("Remove ${collection.label}?") },
            text = { Text("Remove this folder from Your Notes? Your original files will be kept.") },
            confirmButton = {
                TextButton(onClick = {
                    store.remove(collection.id)
                    removing = null
                }) {
                    Text("Remove")
                }
            },
            dismissButton = { TextButton(onClick = { removing = null }) { Text("Cancel") } },
            containerColor = EnsuColor.backgroundBase()
        )
    }
}
