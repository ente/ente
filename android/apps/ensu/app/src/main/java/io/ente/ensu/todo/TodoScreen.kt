package io.ente.ensu.todo

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Context
import android.text.format.DateFormat
import android.text.format.DateUtils
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import io.ente.ensu.bindings.TodoItem
import io.ente.ensu.components.CompactButton
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuCornerRadius
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.designsystem.HugeIcons
import java.util.Calendar

@Composable
fun TodoScreen(store: TodoStore) {
    val state by store.state.collectAsState()
    var title by rememberSaveable { mutableStateOf("") }
    var dueAtMs by rememberSaveable { mutableStateOf<Long?>(null) }
    var editing by remember { mutableStateOf<TodoItem?>(null) }
    var editorOpened by remember { mutableStateOf(0) }
    var adding by remember { mutableStateOf(false) }
    val todos = state.todos

    LaunchedEffect(store) { store.reload() }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(horizontal = EnsuSpacing.pageHorizontal.dp),
        contentPadding = PaddingValues(vertical = EnsuSpacing.lg.dp),
        verticalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp),
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp)) {
                TodoTitleField(value = title, onValueChange = { title = it }, label = "New To Do")
                Row(verticalAlignment = Alignment.CenterVertically) {
                    DueButton(
                        dueAtMs = dueAtMs,
                        onChange = { dueAtMs = it },
                        modifier = Modifier.weight(1f),
                    )
                    CompactButton(
                        label = "Add",
                        onClick = {
                            if (title.isBlank() || adding) return@CompactButton
                            adding = true
                            val added = title
                            store.create(added, dueAtMs) { saved ->
                                adding = false
                                if (saved && title == added) {
                                    title = ""
                                    dueAtMs = null
                                }
                            }
                        },
                    )
                }
            }
        }
        state.error?.let { error ->
            item { Text(error, style = EnsuTypography.small, color = EnsuColor.error) }
        }
        if (state.loaded && todos.isEmpty()) {
            item {
                Text(
                    "Nothing yet. Add one here, or ask in chat.",
                    style = EnsuTypography.small,
                    color = EnsuColor.textMuted(),
                    modifier = Modifier.padding(top = EnsuSpacing.md.dp),
                )
            }
        }
        items(todos, key = { it.id }) { todo ->
            TodoRow(
                todo = todo,
                onToggle = { store.setCompleted(todo, it) },
                onEdit = {
                    store.dismissError()
                    editing = todo
                    editorOpened++
                },
                onDelete = { store.delete(todo) },
            )
        }
    }

    editing?.let { todo ->
        TodoEditDialog(
            todo = todo,
            error = state.error,
            onDismiss = {
                editing = null
                editorOpened++
            },
            onSave = { newTitle, newDue ->
                val opened = editorOpened
                store.update(todo, newTitle, newDue) { saved ->
                    if (saved && editorOpened == opened) editing = null
                }
            },
        )
    }
}

@Composable
private fun TodoRow(
    todo: TodoItem,
    onToggle: (Boolean) -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    val context = LocalContext.current
    val open = todo.isOpen
    Row(verticalAlignment = Alignment.CenterVertically) {
        Checkbox(
            checked = !open,
            onCheckedChange = onToggle,
            modifier = Modifier.semantics { contentDescription = todo.title },
            colors =
                CheckboxDefaults.colors(
                    checkedColor = EnsuColor.action(),
                    uncheckedColor = EnsuColor.textMuted(),
                    checkmarkColor = EnsuColor.backgroundBase(),
                ),
        )
        Column(
            modifier =
                Modifier.weight(1f)
                    .clickable(onClickLabel = "Edit", onClick = onEdit)
                    .padding(vertical = EnsuSpacing.sm.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = todo.title,
                style = EnsuTypography.body,
                color = if (open) EnsuColor.textPrimary() else EnsuColor.textMuted(),
                textDecoration = if (open) TextDecoration.None else TextDecoration.LineThrough,
            )
            todo.dueAtMs?.let { due ->
                Text(
                    text = formatDue(context, due),
                    style = EnsuTypography.mini,
                    color =
                        if (open && due < System.currentTimeMillis()) EnsuColor.error
                        else EnsuColor.textMuted(),
                )
            }
        }
        IconButton(onClick = onDelete, modifier = Modifier.size(48.dp)) {
            Icon(
                painter = painterResource(HugeIcons.Delete01Icon),
                contentDescription = "Delete ${todo.title}",
                modifier = Modifier.size(18.dp),
                tint = EnsuColor.textMuted(),
            )
        }
    }
}

@Composable
private fun TodoEditDialog(
    todo: TodoItem,
    error: String?,
    onDismiss: () -> Unit,
    onSave: (String, Long?) -> Unit,
) {
    var title by rememberSaveable(todo.id) { mutableStateOf(todo.title) }
    var dueAtMs by rememberSaveable(todo.id) { mutableStateOf(todo.dueAtMs) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Edit To Do", style = EnsuTypography.h3) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp)) {
                TodoTitleField(value = title, onValueChange = { title = it }, label = "Title")
                DueButton(dueAtMs = dueAtMs, onChange = { dueAtMs = it })
                error?.let { Text(it, style = EnsuTypography.small, color = EnsuColor.error) }
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(title, dueAtMs) }, enabled = title.isNotBlank()) {
                Text("Save", color = EnsuColor.textPrimary())
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel", color = EnsuColor.textMuted()) }
        },
        containerColor = EnsuColor.backgroundBase(),
    )
}

@Composable
private fun TodoTitleField(value: String, onValueChange: (String) -> Unit, label: String) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth(),
        placeholder = { Text(label, style = EnsuTypography.body, color = EnsuColor.textMuted()) },
        singleLine = true,
        textStyle = EnsuTypography.body,
        colors =
            TextFieldDefaults.colors(
                focusedContainerColor = EnsuColor.fillFaint(),
                unfocusedContainerColor = EnsuColor.fillFaint(),
                focusedIndicatorColor = EnsuColor.fillFaint(),
                unfocusedIndicatorColor = EnsuColor.fillFaint(),
            ),
        shape = RoundedCornerShape(EnsuCornerRadius.input.dp),
    )
}

@Composable
private fun DueButton(
    dueAtMs: Long?,
    onChange: (Long?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = { pickDue(context, dueAtMs, onChange) }) {
            Text(
                text = dueAtMs?.let { formatDue(context, it) } ?: "Add due date",
                style = EnsuTypography.small,
                color = if (dueAtMs == null) EnsuColor.textMuted() else EnsuColor.textPrimary(),
            )
        }
        if (dueAtMs != null) {
            Spacer(modifier = Modifier.width(EnsuSpacing.xs.dp))
            IconButton(onClick = { onChange(null) }, modifier = Modifier.size(36.dp)) {
                Icon(
                    painter = painterResource(HugeIcons.Cancel01Icon),
                    contentDescription = "Clear due date",
                    modifier = Modifier.size(16.dp),
                    tint = EnsuColor.textMuted(),
                )
            }
        }
    }
}

private fun pickDue(context: Context, current: Long?, onChange: (Long?) -> Unit) {
    val calendar =
        Calendar.getInstance().apply {
            if (current != null) {
                timeInMillis = current
            } else {
                add(Calendar.HOUR_OF_DAY, 1)
                set(Calendar.MINUTE, 0)
            }
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
    DatePickerDialog(
            context,
            { _, year, month, day ->
                calendar.set(year, month, day)
                TimePickerDialog(
                        context,
                        { _, hour, minute ->
                            calendar.set(Calendar.HOUR_OF_DAY, hour)
                            calendar.set(Calendar.MINUTE, minute)
                            onChange(calendar.timeInMillis)
                        },
                        calendar.get(Calendar.HOUR_OF_DAY),
                        calendar.get(Calendar.MINUTE),
                        DateFormat.is24HourFormat(context),
                    )
                    .show()
            },
            calendar.get(Calendar.YEAR),
            calendar.get(Calendar.MONTH),
            calendar.get(Calendar.DAY_OF_MONTH),
        )
        .show()
}

private fun formatDue(context: Context, dueAtMs: Long): String =
    DateUtils.formatDateTime(
        context,
        dueAtMs,
        DateUtils.FORMAT_SHOW_WEEKDAY or
            DateUtils.FORMAT_ABBREV_WEEKDAY or
            DateUtils.FORMAT_SHOW_DATE or
            DateUtils.FORMAT_ABBREV_MONTH or
            DateUtils.FORMAT_SHOW_TIME,
    )
