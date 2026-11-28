package io.ente.auth.watch

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.edit
import androidx.wear.compose.foundation.lazy.TransformingLazyColumn
import androidx.wear.compose.foundation.lazy.TransformingLazyColumnState
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberTransformingLazyColumnState
import androidx.wear.compose.material3.AlertDialog
import androidx.wear.compose.material3.AlertDialogDefaults
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.Card
import androidx.wear.compose.material3.CardDefaults
import androidx.wear.compose.material3.CompactButton
import androidx.wear.compose.material3.Icon
import androidx.wear.compose.material3.IconButtonDefaults
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.SurfaceTransformation
import androidx.wear.compose.material3.SwitchButton
import androidx.wear.compose.material3.Text
import androidx.wear.compose.material3.lazy.rememberTransformationSpec
import androidx.wear.compose.material3.lazy.transformedHeight
import io.ente.auth.watch.app.R
import kotlinx.coroutines.delay

class WatchActivity : ComponentActivity() {
    private lateinit var companion: WatchCompanion
    private var companionState by mutableStateOf(WatchCompanion.State())
    private var resumed by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        window.setBackgroundDrawableResource(android.R.color.black)
        companion = WatchCompanion(this)
        companion.onChange = { next -> companionState = next }
        setContent {
            AuthWatchTheme {
                AuthWatchRoot(
                    state = companionState,
                    resumed = resumed,
                    companion = companion,
                    onRequestUnlock = ::requestWatchUnlock,
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        companion.setVisible(true)
    }

    override fun onPause() {
        resumed = false
        companion.setVisible(false)
        super.onPause()
    }

    override fun onDestroy() {
        companion.close()
        super.onDestroy()
    }

    private fun requestWatchUnlock() {
        @Suppress("DEPRECATION")
        val intent = getSystemService(KeyguardManager::class.java)
            .createConfirmDeviceCredentialIntent(
                getString(R.string.app_name),
                null,
            )
            ?: Intent(Settings.ACTION_SECURITY_SETTINGS)
        startActivity(intent)
    }
}

@Composable
private fun AuthWatchRoot(
    state: WatchCompanion.State,
    resumed: Boolean,
    companion: WatchCompanion,
    onRequestUnlock: () -> Unit,
) {
    val context = LocalContext.current
    var selectedEntryId by rememberSaveable { mutableStateOf<String?>(null) }
    val preferences = remember { context.getSharedPreferences("watch", Context.MODE_PRIVATE) }
    var selectedTag by remember { mutableStateOf(preferences.getString("selectedTag", null)) }
    var hideCodes by remember { mutableStateOf(preferences.getBoolean("hideCodes", false)) }
    var pickingTag by rememberSaveable { mutableStateOf(false) }
    var managing by rememberSaveable { mutableStateOf(false) }
    val accountsListState = rememberTransformingLazyColumnState()
    var seconds by remember { mutableLongStateOf(System.currentTimeMillis() / 1000) }

    LaunchedEffect(resumed) {
        if (!resumed) return@LaunchedEffect
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        while (true) {
            if (keyguard.isDeviceLocked) {
                companion.setVisible(false)
                break
            }
            val nowMs = System.currentTimeMillis()
            seconds = nowMs / 1000
            delay((1000L - nowMs % 1000L).coerceAtLeast(16L))
        }
    }

    val availableTags = remember(state.entries) {
        state.entries.flatMap { it.tags }.distinct().sorted()
    }
    val currentTag = selectedTag?.takeIf { it in availableTags }
    val selectedEntry = state.entries.firstOrNull { it.id == selectedEntryId }

    LaunchedEffect(selectedTag) {
        preferences.edit { putString("selectedTag", selectedTag) }
    }
    LaunchedEffect(hideCodes) {
        preferences.edit { putBoolean("hideCodes", hideCodes) }
    }

    val isHidden = state.message == WatchCompanion.Message.hidden
    LaunchedEffect(isHidden, state.entries, availableTags) {
        if (!isHidden) {
            if (selectedTag != null && selectedTag !in availableTags) selectedTag = null
            if (selectedEntryId != null && selectedEntry == null) selectedEntryId = null
        }
    }
    BackHandler(enabled = !isHidden && selectedEntry != null) {
        selectedEntryId = null
    }
    BackHandler(enabled = !isHidden && pickingTag) {
        pickingTag = false
    }
    BackHandler(enabled = !isHidden && managing) {
        managing = false
    }

    AppScaffold {
        if (isHidden) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = stringResource(R.string.codes_hidden),
                    style = MaterialTheme.typography.titleMedium,
                    textAlign = TextAlign.Center,
                )
            }
        } else {
            if (selectedEntry != null) {
                CodeScreen(
                    entry = selectedEntry,
                    seconds = seconds,
                )
            } else if (pickingTag) {
                TagPickerScreen(
                    tags = availableTags,
                    selectedTag = currentTag,
                    onSelectTag = {
                        selectedTag = it
                        pickingTag = false
                    },
                )
            } else if (managing) {
                ManageScreen(
                    hideCodes = hideCodes,
                    onHideCodesChange = { hideCodes = it },
                    onRetry = companion::retry,
                    onErase = {
                        companion.erase()
                        managing = false
                    },
                )
            } else {
                AccountsScreen(
                    state = state,
                    listState = accountsListState,
                    seconds = seconds,
                    availableTags = availableTags,
                    selectedTag = currentTag,
                    hideCodes = hideCodes,
                    onPickTag = { pickingTag = true },
                    onSelectEntry = { selectedEntryId = it },
                    onEnroll = companion::enroll,
                    onUnlock = onRequestUnlock,
                    onManage = { managing = true },
                )
            }
        }
    }
}

@Composable
private fun AccountsScreen(
    state: WatchCompanion.State,
    listState: TransformingLazyColumnState,
    seconds: Long,
    availableTags: List<String>,
    selectedTag: String?,
    hideCodes: Boolean,
    onPickTag: () -> Unit,
    onSelectEntry: (String) -> Unit,
    onEnroll: () -> Unit,
    onUnlock: () -> Unit,
    onManage: () -> Unit,
) {
    val transformationSpec = rememberTransformationSpec()
    val statusText = remember(state.message, state.entries) {
        if (state.message == WatchCompanion.Message.offline && state.entries.isNotEmpty()) null
        else statusStringRes(state.message)
    }?.let { stringResource(it) }.orEmpty()
    val filteredEntries = remember(state.entries, selectedTag) {
        if (selectedTag == null) state.entries
        else state.entries.filter { selectedTag in it.tags }
    }
    val sharedPeriod = if (hideCodes) null else filteredEntries.map { it.period }.distinct().singleOrNull()

    ScreenScaffold(scrollState = listState) { contentPadding ->
        if (sharedPeriod != null) {
            val remaining = (sharedPeriod - seconds % sharedPeriod).toInt()
            CountdownRing(
                progress = remaining.toFloat() / sharedPeriod,
                color = if (remaining <= 5) WatchStyle.warning else WatchStyle.accent,
                modifier = Modifier.fillMaxSize().padding(3.dp),
            )
        }
        TransformingLazyColumn(
            state = listState,
            contentPadding = contentPadding,
            modifier = Modifier.fillMaxSize().padding(horizontal = if (sharedPeriod != null) 6.dp else 0.dp),
        ) {
            if (availableTags.isEmpty()) {
                item(key = "title") {
                    ScreenTitle(stringResource(R.string.app_name))
                }
            } else {
                item(key = "tag-filter") {
                    TagFilterButton(selectedTag = selectedTag, onClick = onPickTag)
                }
            }
            if (statusText.isNotEmpty()) {
                item(key = "status") {
                    Text(
                        text = statusText,
                        style = MaterialTheme.typography.bodySmall,
                        color = WatchStyle.secondary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
                    )
                }
            }
            if (state.message == WatchCompanion.Message.unlockWatch) {
                item(key = "unlock") {
                    Button(
                        onClick = onUnlock,
                        transformation = SurfaceTransformation(transformationSpec),
                        modifier = Modifier.fillMaxWidth().transformedHeight(this, transformationSpec),
                    ) {
                        Text(stringResource(R.string.unlock))
                    }
                }
            }
            items(filteredEntries, key = { it.id }) { entry ->
                AccountCard(
                    entry = entry,
                    seconds = seconds,
                    hideCodes = hideCodes,
                    showsBar = sharedPeriod == null,
                    onClick = { onSelectEntry(entry.id) },
                    transformation = SurfaceTransformation(transformationSpec),
                    modifier = Modifier.fillMaxWidth().transformedHeight(this, transformationSpec),
                )
            }
            if (state.canEnroll) {
                item(key = "enroll") {
                    Button(
                        onClick = onEnroll,
                        transformation = SurfaceTransformation(transformationSpec),
                        modifier = Modifier.fillMaxWidth().transformedHeight(this, transformationSpec),
                    ) {
                        Text(stringResource(R.string.setup))
                    }
                }
            }
            if (state.canErase) {
                item(key = "manage") {
                    Button(
                        onClick = onManage,
                        colors = ButtonDefaults.filledTonalButtonColors(),
                        transformation = SurfaceTransformation(transformationSpec),
                        modifier = Modifier.fillMaxWidth().transformedHeight(this, transformationSpec),
                    ) {
                        Text(stringResource(R.string.manage))
                    }
                }
            }
        }
    }
}

@Composable
private fun ManageScreen(
    hideCodes: Boolean,
    onHideCodesChange: (Boolean) -> Unit,
    onRetry: () -> Unit,
    onErase: () -> Unit,
) {
    var confirmErase by remember { mutableStateOf(false) }
    val listState = rememberTransformingLazyColumnState()
    val transformationSpec = rememberTransformationSpec()

    ScreenScaffold(scrollState = listState) { contentPadding ->
        TransformingLazyColumn(
            state = listState,
            contentPadding = contentPadding,
            modifier = Modifier.fillMaxSize(),
        ) {
            item(key = "title") {
                ScreenTitle(stringResource(R.string.manage))
            }
            item(key = "hide-codes") {
                SwitchButton(
                    checked = hideCodes,
                    onCheckedChange = onHideCodesChange,
                    transformation = SurfaceTransformation(transformationSpec),
                    modifier = Modifier.fillMaxWidth().transformedHeight(this, transformationSpec),
                ) {
                    Text(stringResource(R.string.hide_codes))
                }
            }
            item(key = "sync") {
                Button(
                    onClick = onRetry,
                    colors = ButtonDefaults.filledTonalButtonColors(),
                    transformation = SurfaceTransformation(transformationSpec),
                    modifier = Modifier.fillMaxWidth().transformedHeight(this, transformationSpec),
                ) {
                    Text(stringResource(R.string.sync))
                }
            }
            item(key = "erase") {
                Button(
                    onClick = { confirmErase = true },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color.Black,
                        contentColor = WatchStyle.destructive,
                    ),
                    transformation = SurfaceTransformation(transformationSpec),
                    modifier = Modifier.fillMaxWidth().transformedHeight(this, transformationSpec),
                ) {
                    Text(stringResource(R.string.erase))
                }
            }
        }
    }
    EraseConfirmation(
        visible = confirmErase,
        onDismiss = { confirmErase = false },
        onErase = onErase,
    )
}

@Composable
private fun ScreenTitle(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp),
    )
}

@Composable
private fun TagFilterButton(selectedTag: String?, onClick: () -> Unit) {
    Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        CompactButton(
            onClick = onClick,
            icon = {
                Icon(
                    painter = painterResource(R.drawable.ic_filter),
                    contentDescription = stringResource(R.string.filter_by_tag),
                    modifier = Modifier.size(ButtonDefaults.ExtraSmallIconSize),
                )
            },
            colors = ButtonDefaults.buttonColors(
                containerColor = if (selectedTag != null) WatchStyle.accent else WatchStyle.surface,
            ),
        ) {
            Text(
                text = selectedTag ?: stringResource(R.string.all_tags),
                style = MaterialTheme.typography.labelSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun TagPickerScreen(
    tags: List<String>,
    selectedTag: String?,
    onSelectTag: (String?) -> Unit,
) {
    val listState = rememberTransformingLazyColumnState(
        initialAnchorItemIndex = selectedTag?.let { tags.indexOf(it) + 2 } ?: 0,
    )
    val transformationSpec = rememberTransformationSpec()

    ScreenScaffold(scrollState = listState) { contentPadding ->
        TransformingLazyColumn(
            state = listState,
            contentPadding = contentPadding,
            modifier = Modifier.fillMaxSize(),
        ) {
            item(key = "title") {
                ScreenTitle(stringResource(R.string.tags))
            }
            item(key = "all") {
                TagOption(
                    label = stringResource(R.string.all_tags),
                    selected = selectedTag == null,
                    onClick = { onSelectTag(null) },
                    transformation = SurfaceTransformation(transformationSpec),
                    modifier = Modifier.fillMaxWidth().transformedHeight(this, transformationSpec),
                )
            }
            items(tags, key = { "tag:$it" }) { tag ->
                TagOption(
                    label = tag,
                    selected = selectedTag == tag,
                    onClick = { onSelectTag(tag) },
                    transformation = SurfaceTransformation(transformationSpec),
                    modifier = Modifier.fillMaxWidth().transformedHeight(this, transformationSpec),
                )
            }
        }
    }
}

@Composable
private fun TagOption(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    transformation: SurfaceTransformation,
    modifier: Modifier = Modifier,
) {
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(
            containerColor = if (selected) WatchStyle.accent else WatchStyle.surface,
        ),
        transformation = transformation,
        modifier = modifier.semantics { this.selected = selected },
    ) {
        Text(text = label, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun AccountCard(
    entry: Entry,
    seconds: Long,
    hideCodes: Boolean,
    showsBar: Boolean,
    onClick: () -> Unit,
    transformation: SurfaceTransformation,
    modifier: Modifier = Modifier,
) {
    val label = listOf(entry.issuer, entry.account).filter { it.isNotEmpty() }.joinToString(", ")
    val codeValue = if (hideCodes) null else entry.code(seconds)
    val remaining = if (hideCodes) null else (entry.period - seconds % entry.period).toInt()
    val spokenDesc = codeValue?.let {
        "$label, ${stringResource(R.string.code_spoken, it.toCharArray().joinToString(" "))}"
    } ?: label

    Card(
        onClick = onClick,
        transformation = transformation,
        colors = CardDefaults.cardColors(contentColor = Color.White),
        modifier = modifier.semantics(mergeDescendants = true) {
            contentDescription = spokenDesc
        },
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                text = entry.issuer.ifEmpty { entry.account },
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            if (entry.pinned) {
                Icon(
                    painter = painterResource(R.drawable.ic_pin),
                    contentDescription = stringResource(R.string.pinned),
                    tint = WatchStyle.secondary,
                    modifier = Modifier.size(14.dp),
                )
            }
        }
        if (entry.issuer.isNotEmpty() && entry.account.isNotEmpty()) {
            Text(
                text = entry.account,
                style = MaterialTheme.typography.bodySmall,
                color = WatchStyle.secondary,
                maxLines = 1,
                overflow = TextOverflow.MiddleEllipsis,
            )
        }
        if (codeValue != null && remaining != null) {
            val isWarning = remaining <= 5
            Spacer(modifier = Modifier.height(4.dp))
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                Text(
                    text = formatCode(codeValue),
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                    fontSize = 20.sp,
                    color = if (isWarning) WatchStyle.warning else Color.White,
                    maxLines = 1,
                )
            }
            if (showsBar) {
                Spacer(modifier = Modifier.height(4.dp))
                CountdownBar(
                    progress = remaining.toFloat() / entry.period,
                    color = if (isWarning) WatchStyle.warning else WatchStyle.accent,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun CodeScreen(entry: Entry, seconds: Long) {
    val scrollState = rememberScrollState()
    val codeValue = entry.code(seconds)
    val formatted = formatCode(codeValue)
    val spoken = stringResource(R.string.code_spoken, codeValue.toCharArray().joinToString(" "))
    val remaining = (entry.period - seconds % entry.period).toInt()
    val isWarning = remaining <= 5
    val spokenRemaining = pluralStringResource(R.plurals.seconds_remaining, remaining, remaining)

    ScreenScaffold(scrollState = scrollState) { contentPadding ->
        CountdownRing(
            progress = remaining.toFloat() / entry.period,
            color = if (isWarning) WatchStyle.warning else WatchStyle.accent,
            modifier = Modifier.fillMaxSize().padding(3.dp),
        )
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(scrollState)
                .padding(contentPadding)
                .padding(horizontal = 12.dp, vertical = 8.dp),
        ) {
            Text(
                text = entry.issuer.ifEmpty { stringResource(R.string.code) },
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.Center,
            )
            if (entry.account.isNotEmpty()) {
                Text(
                    text = entry.account,
                    style = MaterialTheme.typography.bodySmall,
                    color = WatchStyle.secondary,
                    textAlign = TextAlign.Center,
                )
            }
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                BasicText(
                    text = formatted,
                    style = TextStyle(
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.Bold,
                        fontSize = 34.sp,
                        color = if (isWarning) WatchStyle.warning else Color.White,
                    ),
                    maxLines = 1,
                    softWrap = false,
                    autoSize = TextAutoSize.StepBased(minFontSize = 16.sp, maxFontSize = 34.sp),
                    modifier = Modifier.semantics { contentDescription = "$spoken, $spokenRemaining" },
                )
            }
            val nextCodeValue = entry.code(seconds + entry.period)
            val spokenNext = stringResource(
                R.string.next_code_spoken, nextCodeValue.toCharArray().joinToString(" "),
            )
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                Text(
                    text = stringResource(R.string.next_code, formatCode(nextCodeValue)),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (isWarning) Color.White else WatchStyle.secondary,
                    maxLines = 1,
                    modifier = Modifier.semantics { contentDescription = spokenNext },
                )
            }
        }
    }
}

@Composable
private fun CountdownBar(progress: Float, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier = modifier.height(4.dp).clearAndSetSemantics {}) {
        val radius = CornerRadius(size.height / 2)
        drawRoundRect(color = WatchStyle.track, cornerRadius = radius)
        drawRoundRect(color = color, size = Size(size.width * progress, size.height), cornerRadius = radius)
    }
}

@Composable
private fun CountdownRing(progress: Float, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier = modifier.clearAndSetSemantics {}) {
        val stroke = Stroke(width = 5.dp.toPx(), cap = StrokeCap.Round)
        val diameter = size.minDimension - stroke.width
        val topLeft = Offset((size.width - diameter) / 2, (size.height - diameter) / 2)
        val arcSize = Size(diameter, diameter)
        drawArc(WatchStyle.track, RING_START, RING_SWEEP, false, topLeft, arcSize, style = stroke)
        drawArc(color, RING_START, RING_SWEEP * progress, false, topLeft, arcSize, style = stroke)
    }
}

private const val RING_START = 295.5f
private const val RING_SWEEP = 310f

@Composable
private fun EraseConfirmation(visible: Boolean, onDismiss: () -> Unit, onErase: () -> Unit) {
    val eraseActionLabel = stringResource(R.string.erase_action)
    AlertDialog(
        visible = visible,
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.erase_title)) },
        text = { Text(stringResource(R.string.erase_description)) },
        confirmButton = {
            AlertDialogDefaults.ConfirmButton(
                onClick = {
                    onDismiss()
                    onErase()
                },
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = WatchStyle.destructive,
                ),
                modifier = Modifier.semantics { contentDescription = eraseActionLabel },
            )
        },
        dismissButton = {
            AlertDialogDefaults.DismissButton(
                onClick = { onDismiss() },
            )
        },
    )
}

private fun statusStringRes(message: WatchCompanion.Message): Int? = when (message) {
    WatchCompanion.Message.setup -> R.string.setup_instructions
    WatchCompanion.Message.approvePhone -> R.string.approve_phone
    WatchCompanion.Message.noAccounts -> R.string.no_accounts
    WatchCompanion.Message.offline -> R.string.offline
    WatchCompanion.Message.unlockWatch -> R.string.unlock_watch
    WatchCompanion.Message.storageFailed -> R.string.storage_failed
    WatchCompanion.Message.secureStorageUnavailable -> R.string.secure_storage_unavailable
    WatchCompanion.Message.setupFailed -> R.string.setup_failed
    WatchCompanion.Message.syncFailed -> R.string.sync_failed
    WatchCompanion.Message.connectPhone -> R.string.connect_phone
    WatchCompanion.Message.ready, WatchCompanion.Message.hidden -> null
}
