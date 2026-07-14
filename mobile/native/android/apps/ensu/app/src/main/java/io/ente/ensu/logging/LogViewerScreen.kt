package io.ente.ensu.logging

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.os.Build
import android.widget.Toast
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuCornerRadius
import io.ente.ensu.designsystem.EnsuIcon
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.designsystem.HugeIcons
import io.ente.ensu.logging.LogEntry
import io.ente.ensu.logging.LogLevel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun LogViewerScreen(
    logRepository: FileLogRepository
) {
    var entries by remember { mutableStateOf<List<LogEntry>>(emptyList()) }
    var selectedLog by remember { mutableStateOf<LogEntry?>(null) }
    var query by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        entries = logRepository.readTodayEntries()
    }

    val filteredLogs = remember(entries, query) {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return@remember entries
        entries.filter { entry ->
            entry.message.lowercase().contains(q) ||
                (entry.tag?.lowercase()?.contains(q) == true) ||
                (entry.details?.lowercase()?.contains(q) == true)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(EnsuSpacing.pageHorizontal.dp)
    ) {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text(text = "Search logs", style = EnsuTypography.body) },
            singleLine = true,
            colors = TextFieldDefaults.colors(
                focusedContainerColor = EnsuColor.fillFaint(),
                unfocusedContainerColor = EnsuColor.fillFaint(),
                focusedIndicatorColor = EnsuColor.fillFaint(),
                unfocusedIndicatorColor = EnsuColor.fillFaint()
            ),
            shape = RoundedCornerShape(EnsuCornerRadius.input.dp)
        )

        Spacer(modifier = Modifier.height(EnsuSpacing.lg.dp))

        if (filteredLogs.isEmpty()) {
            Text(text = "No logs available", style = EnsuTypography.body, color = EnsuColor.textMuted())
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp)) {
                items(filteredLogs, key = { it.id }) { log ->
                    LogRow(logEntry = log, onOpenDetails = { selectedLog = log })
                }
            }
        }
    }

    selectedLog?.let { log ->
        NativeLogDetailsDialog(logEntry = log, onDismiss = { selectedLog = null })
    }
}

@Composable
private fun NativeLogDetailsDialog(logEntry: LogEntry, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val message = remember(logEntry) {
        buildString {
            append("Level: ")
            append(logEntry.level.name)
            logEntry.tag?.let { tag ->
                append("\nTag: ")
                append(tag)
            }
            append("\n\n")
            append(logEntry.message)
            logEntry.details?.let { details ->
                if (details.isNotBlank()) {
                    append("\n\nDetails:\n")
                    append(details)
                }
            }
        }
    }

    DisposableEffect(logEntry) {
        val dialog = AlertDialog.Builder(context)
            .setTitle("Log details")
            .setMessage(message)
            .setNeutralButton("Copy") { _, _ ->
                context.getSystemService(ClipboardManager::class.java)
                    .setPrimaryClip(ClipData.newPlainText("log", message))
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    Toast.makeText(context, "Copied", Toast.LENGTH_SHORT).show()
                }
            }
            .setPositiveButton("Close") { _, _ -> onDismiss() }
            .setOnDismissListener { onDismiss() }
            .create()

        dialog.show()
        onDispose { dialog.dismiss() }
    }
}

@Composable
private fun LogRow(logEntry: LogEntry, onOpenDetails: () -> Unit) {
    val hasDetails = !logEntry.details.isNullOrBlank()

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpenDetails)
            .padding(vertical = EnsuSpacing.xs.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                modifier = Modifier.weight(1f),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size(7.dp)
                        .background(levelColor(logEntry.level), CircleShape)
                )
                Spacer(modifier = Modifier.width(EnsuSpacing.sm.dp))
                logEntry.tag?.let { tag ->
                    Text(
                        text = tag,
                        style = EnsuTypography.mini,
                        color = EnsuColor.textMuted(),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            Spacer(modifier = Modifier.width(EnsuSpacing.sm.dp))
            Text(
                text = logTimestampFormatter.format(Date(logEntry.timestampMillis)),
                style = EnsuTypography.mini,
                color = EnsuColor.textMuted()
            )
            Box(modifier = Modifier.size(EnsuIcon.tiny)) {
                if (hasDetails) {
                    Icon(
                        painter = painterResource(HugeIcons.ArrowRight01Icon),
                        contentDescription = null,
                        tint = EnsuColor.textMuted(),
                        modifier = Modifier.size(EnsuIcon.tiny)
                    )
                }
            }
        }
        Spacer(modifier = Modifier.height(EnsuSpacing.xs.dp))
        Text(text = logEntry.message, style = EnsuTypography.body)
    }
}

@Composable
private fun levelColor(level: LogLevel): Color = when (level) {
    LogLevel.Info -> EnsuColor.textMuted()
    LogLevel.Warning -> EnsuColor.accent()
    LogLevel.Error -> EnsuColor.error
}

private val logTimestampFormatter = SimpleDateFormat("MMM d, h:mm:ss a", Locale.getDefault())
