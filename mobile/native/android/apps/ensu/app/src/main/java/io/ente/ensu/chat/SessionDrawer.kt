package io.ente.ensu.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.graphics.RectangleShape

import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalDrawerSheet
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
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuCornerRadius
import io.ente.ensu.designsystem.HugeIcons
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.chat.ChatSession
import kotlin.math.absoluteValue

@Composable
fun SessionDrawer(
    sessions: List<ChatSession>,
    selectedSessionId: String?,
    onSelectSession: (ChatSession) -> Unit,
    onDeleteSession: (ChatSession) -> Unit,
    onOpenSettings: () -> Unit
) {
    var searchQuery by remember { mutableStateOf("") }
    val filteredSessions = remember(searchQuery, sessions) {
        val query = searchQuery.trim()
        if (query.isEmpty()) {
            sessions
        } else {
            val lower = query.lowercase()
            sessions.filter { session ->
                session.title.lowercase().contains(lower) ||
                    (session.lastMessagePreview?.lowercase()?.contains(lower) == true)
            }
        }
    }

    ModalDrawerSheet(
        drawerContainerColor = EnsuColor.backgroundBase(),
        drawerShape = RectangleShape
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.systemBars)
        ) {
            DrawerHeader(
                searchQuery = searchQuery,
                onSearchChange = { searchQuery = it }
            )

            HorizontalDivider(color = EnsuColor.border())

            SessionGroups(
                sessions = filteredSessions,
                selectedSessionId = selectedSessionId,
                onSelectSession = onSelectSession,
                onDeleteSession = onDeleteSession,
                modifier = Modifier.weight(1f)
            )

            HorizontalDivider(color = EnsuColor.border())

            DrawerFooter(
                onOpenSettings = onOpenSettings
            )
        }
    }
}

@Composable
private fun DrawerHeader(
    searchQuery: String,
    onSearchChange: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(EnsuColor.backgroundBase())
            .padding(horizontal = EnsuSpacing.lg.dp, vertical = EnsuSpacing.md.dp)
    ) {
        DrawerSearchControls(
            query = searchQuery,
            onQueryChange = onSearchChange,
            onClearSearch = { onSearchChange("") },
            modifier = Modifier.fillMaxWidth()
        )
    }
}

@Composable
private fun DrawerSearchControls(
    query: String,
    onQueryChange: (String) -> Unit,
    onClearSearch: () -> Unit,
    modifier: Modifier = Modifier
) {
    val hasQuery = query.isNotBlank()

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        DrawerSearchField(
            query = query,
            onQueryChange = onQueryChange,
            modifier = Modifier.weight(1f)
        )

        if (hasQuery) {
            DrawerSearchActionButton(
                iconRes = HugeIcons.Cancel01Icon,
                contentDescription = "Clear search",
                onClick = onClearSearch
            )
        }
    }
}

@Composable
private fun DrawerSearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    OutlinedTextField(
        value = query,
        onValueChange = onQueryChange,
        modifier = modifier,
        placeholder = {
            Text(
                text = "Search chats",
                style = EnsuTypography.body,
                color = EnsuColor.textMuted()
            )
        },
        leadingIcon = {
            Icon(
                painter = painterResource(HugeIcons.Search01Icon),
                contentDescription = "Search",
                modifier = Modifier.size(18.dp),
                tint = EnsuColor.textMuted()
            )
        },
        singleLine = true,
        textStyle = EnsuTypography.body,
        colors = TextFieldDefaults.colors(
            focusedContainerColor = EnsuColor.fillFaint(),
            unfocusedContainerColor = EnsuColor.fillFaint(),
            focusedIndicatorColor = EnsuColor.fillFaint(),
            unfocusedIndicatorColor = EnsuColor.fillFaint()
        ),
        shape = RoundedCornerShape(EnsuCornerRadius.card.dp)
    )
}

@Composable
private fun DrawerSearchActionButton(
    iconRes: Int,
    contentDescription: String,
    onClick: () -> Unit
) {
    IconButton(
        onClick = onClick,
        modifier = Modifier
            .size(36.dp)
            .clip(CircleShape)
    ) {
        Icon(
            painter = painterResource(iconRes),
            contentDescription = contentDescription,
            modifier = Modifier.size(18.dp),
            tint = EnsuColor.textPrimary()
        )
    }
}

@Composable
private fun SessionGroups(
    sessions: List<ChatSession>,
    selectedSessionId: String?,
    onSelectSession: (ChatSession) -> Unit,
    onDeleteSession: (ChatSession) -> Unit,
    modifier: Modifier = Modifier
) {
    val grouped = remember(sessions) { sessions.groupBy { sessionGroupLabel(it.updatedAtMillis) } }
    val order = listOf("TODAY", "YESTERDAY", "THIS WEEK", "LAST WEEK", "THIS MONTH", "OLDER")
    val orderedGroups = remember(grouped) {
        order.mapNotNull { label ->
            grouped[label]?.takeIf { it.isNotEmpty() }?.let { label to it }
        }
    }

    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(vertical = EnsuSpacing.lg.dp),
        verticalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp)
    ) {
        orderedGroups.forEachIndexed { index, (label, groupSessions) ->
            item(key = "header_$label") {
                Column {
                    if (index > 0) {
                        Spacer(modifier = Modifier.height(EnsuSpacing.md.dp))
                    }
                    Text(
                        text = label,
                        style = EnsuTypography.tiny.copy(letterSpacing = 1.sp),
                        color = EnsuColor.textMuted(),
                        modifier = Modifier.padding(horizontal = EnsuSpacing.lg.dp)
                    )
                }
            }

            items(groupSessions, key = { it.id }) { session ->
                SessionTile(
                    session = session,
                    isSelected = session.id == selectedSessionId,
                    onSelect = { onSelectSession(session) },
                    onDelete = { onDeleteSession(session) }
                )
            }
        }
    }
}

@Composable
private fun SessionTile(
    session: ChatSession,
    isSelected: Boolean,
    onSelect: () -> Unit,
    onDelete: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .padding(horizontal = EnsuSpacing.lg.dp, vertical = EnsuSpacing.sm.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp)
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = session.title,
                    style = if (isSelected) EnsuTypography.body else EnsuTypography.small,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
                    color = EnsuColor.textPrimary(),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                val subtitle = session.lastMessagePreview ?: "Nothing here"
                Text(
                    text = subtitle,
                    style = EnsuTypography.mini,
                    color = EnsuColor.textMuted(),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .clickable(onClick = onDelete),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    painter = painterResource(HugeIcons.Delete01Icon),
                    contentDescription = "Delete",
                    modifier = Modifier.size(18.dp),
                    tint = EnsuColor.textMuted()
                )
            }
        }
    }
}

@Composable
private fun DrawerFooter(
    onOpenSettings: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpenSettings)
            .padding(EnsuSpacing.lg.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(EnsuSpacing.md.dp)
    ) {
        Text(
            text = "Settings",
            style = EnsuTypography.body,
            color = EnsuColor.textPrimary(),
            modifier = Modifier.weight(1f)
        )
        Icon(
            painter = painterResource(HugeIcons.ArrowRight01Icon),
            contentDescription = "Settings",
            modifier = Modifier.size(18.dp),
            tint = EnsuColor.textMuted()
        )
    }
}

private fun sessionGroupLabel(updatedAtMillis: Long): String {
    val now = System.currentTimeMillis()
    val dayMillis = 86_400_000L
    val daysAgo = ((now - updatedAtMillis) / dayMillis).absoluteValue
    return when {
        daysAgo == 0L -> "TODAY"
        daysAgo == 1L -> "YESTERDAY"
        daysAgo < 7L -> "THIS WEEK"
        daysAgo < 14L -> "LAST WEEK"
        daysAgo < 30L -> "THIS MONTH"
        else -> "OLDER"
    }
}
