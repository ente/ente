@file:OptIn(
    androidx.compose.animation.ExperimentalAnimationApi::class,
    androidx.compose.material3.ExperimentalMaterial3Api::class
)

package io.ente.ensu

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.ManagedActivityResultLauncher
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.navigation.compose.currentBackStackEntryAsState
import com.google.accompanist.navigation.animation.rememberAnimatedNavController
import io.ente.ensu.chat.SessionDrawer
import io.ente.ensu.components.ImageAttachmentPreviewDialog
import io.ente.ensu.components.NativeChoiceDialog
import io.ente.ensu.settings.AdvancedSettingsDataStore
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.storage.FilePathManager
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.chat.Attachment
import io.ente.ensu.chat.AttachmentType
import io.ente.ensu.bindings.ConfigDefaults
import io.ente.ensu.chat.MaxImageAttachmentsPerMessage
import io.ente.ensu.AppState
import io.ente.ensu.AppStore
import io.ente.ensu.whatsnew.PendingWhatsNew
import io.ente.ensu.whatsnew.WhatsNewDialog
import io.ente.ensu.whatsnew.WhatsNewService
import io.ente.ensu.bindings.compressAttachmentImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

@Composable
fun HomeView(
    appState: AppState,
    store: AppStore,
    logRepository: FileLogRepository,
    advancedSettingsDataStore: AdvancedSettingsDataStore,
    appVersion: String,
    configDefaults: ConfigDefaults
) {
    val drawerState = androidx.compose.material3.rememberDrawerState(DrawerValue.Closed)
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current
    val navController = rememberAnimatedNavController()
    val lifecycleOwner = LocalLifecycleOwner.current
    val latestStore by rememberUpdatedState(store)
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route ?: HomeRoute.Chat
    val isChatRoute = currentRoute == HomeRoute.Chat
    var deleteSessionTarget by remember { mutableStateOf<io.ente.ensu.chat.ChatSession?>(null) }
    var showLogShareDialog by remember { mutableStateOf(false) }
    var showSignInComingSoon by remember { mutableStateOf(false) }
    var imagePreviewAttachment by remember { mutableStateOf<Attachment?>(null) }
    val whatsNewService = remember(context) { WhatsNewService(context.applicationContext) }
    var pendingWhatsNew by remember { mutableStateOf<PendingWhatsNew?>(null) }

    val handleSignInRequest: () -> Unit = { showSignInComingSoon = true }

    val imagePicker = rememberAttachmentPicker(
        contract = ActivityResultContracts.GetContent(),
        type = AttachmentType.Image,
        store = store,
        context = context
    )

    val documentPicker = rememberAttachmentPicker(
        contract = ActivityResultContracts.OpenDocument(),
        type = AttachmentType.Document,
        store = store,
        context = context
    )

    val exportLogsLauncher = androidx.activity.compose.rememberLauncherForActivityResult(
        contract = androidx.activity.result.contract.ActivityResultContracts.CreateDocument("application/zip")
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            try {
                val zipFile = logRepository.createLogsZip()
                context.contentResolver.openOutputStream(uri)?.use { out ->
                    zipFile.inputStream().use { input -> input.copyTo(out) }
                }
                Toast.makeText(context, "Logs exported", Toast.LENGTH_SHORT).show()
            } catch (err: Throwable) {
                Toast.makeText(context, "Export failed: ${err.message ?: "Unknown error"}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    val shareLogs: () -> Unit = {
        scope.launch {
            try {
                val zipFile = logRepository.createLogsZip()
                val uri = FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    zipFile
                )
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = "application/zip"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                context.startActivity(Intent.createChooser(intent, "Share logs"))
            } catch (err: Throwable) {
                Toast.makeText(context, "Share failed: ${err.message ?: "Unknown error"}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    val exportLogs: () -> Unit = {
        val name = "ensu-logs-${System.currentTimeMillis()}.zip"
        exportLogsLauncher.launch(name)
    }

    val currentSession by remember(appState.chat.sessions, appState.chat.currentSessionId) {
        derivedStateOf {
            appState.chat.sessions.firstOrNull { it.id == appState.chat.currentSessionId }
        }
    }

    BackHandler(enabled = !isChatRoute) {
        if (!navController.popBackStack()) {
            navController.navigate(HomeRoute.Chat) { launchSingleTop = true }
        }
    }

    BackHandler(enabled = drawerState.currentValue == DrawerValue.Open) {
        scope.launch { drawerState.close() }
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                latestStore.refreshModelDownloadInfo()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(whatsNewService) {
        delay(600)
        pendingWhatsNew = whatsNewService.getPendingWhatsNew()
    }

    // Note: Drawer close is handled in navigation callbacks (onOpenSettings, onAccount, etc.)
    // to avoid race conditions with route changes during navigation transitions.

    val openDrawer: () -> Unit = { scope.launch { drawerState.open() } }

    val handleAttachmentSelected: (AttachmentType) -> Unit = handle@{ type ->
        when (type) {
            AttachmentType.Image -> {
                val imageCount = appState.chat.attachments.count {
                    it.type == AttachmentType.Image
                }
                if (imageCount >= MaxImageAttachmentsPerMessage) return@handle
                imagePicker.launch("image/*")
            }
            AttachmentType.Document -> {
                documentPicker.launch(arrayOf("*/*"))
            }
        }
    }

    ModalNavigationDrawer(
        drawerState = drawerState,
        gesturesEnabled = isChatRoute,
        drawerContent = {
            // Always render SessionDrawer - don't conditionally swap content based on route.
            // Changing drawer content while navigating can cause race conditions with the
            // navigation back stack. The drawer is already hidden via gesturesEnabled.
            SessionDrawer(
                sessions = appState.chat.sessions,
                selectedSessionId = appState.chat.currentSessionId,
                onSelectSession = { session ->
                    // Same reason as above: just swap the session in-place.
                    store.selectSession(session.id)
                    store.persistSelectedSession(scope, session.id)
                    scope.launch { drawerState.close() }
                },
                onDeleteSession = { session ->
                    deleteSessionTarget = session
                },
                onOpenSettings = {
                    navController.navigate(HomeRoute.Settings) {
                        launchSingleTop = true
                        restoreState = true
                        popUpTo(HomeRoute.Chat) { inclusive = false }
                    }
                    scope.launch { drawerState.close() }
                }
            )
        }
    ) {
        HomeNavigation(
            appState = appState,
            store = store,
            logRepository = logRepository,
            advancedSettingsDataStore = advancedSettingsDataStore,
            appVersion = appVersion,
            configDefaults = configDefaults,
            navController = navController,
            drawerState = drawerState,
            currentRoute = currentRoute,
            currentSession = currentSession,
            onSignIn = handleSignInRequest,
            onOpenDrawer = openDrawer,
            onNewChat = {
                store.startNewSessionDraft()
                store.persistSelectedSession(scope, null)
            },
            onShowLogShareDialog = { showLogShareDialog = true },
            onAttachmentSelected = handleAttachmentSelected,
            onOpenAttachment = { attachment ->
                if (attachment.type == AttachmentType.Image) {
                    imagePreviewAttachment = attachment
                } else {
                    openAttachment(context, attachment)
                }
            }
        )
    }

    imagePreviewAttachment?.let { attachment ->
        ImageAttachmentPreviewDialog(
            path = attachment.localPath,
            contentDescription = attachment.name,
            onDismiss = { imagePreviewAttachment = null }
        )
    }

    if (showSignInComingSoon) {
        ComingSoonDialog(
            title = "Coming soon",
            message = "Sign in and cloud backup will be available in a future update.",
            onDismiss = { showSignInComingSoon = false }
        )
    }

    pendingWhatsNew?.let { pending ->
        WhatsNewDialog(
            entries = pending.entries,
            onDismiss = {
                whatsNewService.markSeen()
                pendingWhatsNew = null
            }
        )
    }

    if (deleteSessionTarget != null) {
        NativeChoiceDialog(
            title = "Delete Chat",
            body = "This will delete the chat from this device.",
            firstButtonLabel = "Delete",
            secondButtonLabel = "Cancel",
            onFirst = {
                deleteSessionTarget?.let { session ->
                    store.deleteSession(session.id)
                    store.persistSelectedSession(scope, appState.chat.currentSessionId)
                }
                deleteSessionTarget = null
            },
            onSecond = { deleteSessionTarget = null },
            onDismiss = { deleteSessionTarget = null }
        )
    }

    if (showLogShareDialog) {
        ModalBottomSheet(
            onDismissRequest = { showLogShareDialog = false },
            containerColor = EnsuColor.backgroundBase()
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = EnsuSpacing.lg.dp, vertical = EnsuSpacing.md.dp),
                verticalArrangement = Arrangement.spacedBy(EnsuSpacing.md.dp)
            ) {
                Text(text = "Logs", style = EnsuTypography.h3Bold, color = EnsuColor.textPrimary())
                Text(text = "Export or share logs for support.", style = EnsuTypography.body, color = EnsuColor.textMuted())
                Row(horizontalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp)) {
                    TextButton(
                        onClick = {
                            showLogShareDialog = false
                            shareLogs()
                        },
                        colors = ButtonDefaults.textButtonColors(contentColor = EnsuColor.textPrimary())
                    ) {
                        Text(text = "Share")
                    }
                    TextButton(
                        onClick = {
                            showLogShareDialog = false
                            exportLogs()
                        },
                        colors = ButtonDefaults.textButtonColors(contentColor = EnsuColor.textPrimary())
                    ) {
                        Text(text = "Export")
                    }
                    Spacer(modifier = Modifier.weight(1f))
                    TextButton(
                        onClick = { showLogShareDialog = false },
                        colors = ButtonDefaults.textButtonColors(contentColor = EnsuColor.textMuted())
                    ) {
                        Text(text = "Cancel")
                    }
                }
                Spacer(modifier = Modifier.height(EnsuSpacing.md.dp))
            }
        }
    }
}

@Composable
private fun <I> rememberAttachmentPicker(
    contract: ActivityResultContract<I, Uri?>,
    type: AttachmentType,
    store: AppStore,
    context: Context
): ManagedActivityResultLauncher<I, Uri?> {
    val scope = rememberCoroutineScope()
    val latestStore by rememberUpdatedState(store)

    return rememberLauncherForActivityResult(contract = contract) { uri ->
        if (uri != null) {
            latestStore.setAttachmentProcessing(true)
            scope.launch {
                val attachment = withContext(Dispatchers.IO) {
                    buildAttachmentFromUri(context, uri, type)
                }
                if (attachment != null) {
                    latestStore.addAttachment(attachment)
                    if (type == AttachmentType.Image) {
                        latestStore.prewarmImageInferenceIfDownloaded()
                    }
                } else {
                    latestStore.setAttachmentProcessing(false)
                }
            }
        }
    }
}

private fun buildAttachmentFromUri(
    context: Context,
    uri: Uri,
    type: AttachmentType
): Attachment? {
    val resolver = context.contentResolver
    val name = queryDisplayName(resolver, uri)
    val size = querySize(resolver, uri)
    val rawName = name ?: when (type) {
        AttachmentType.Image -> "image"
        AttachmentType.Document -> "document"
    }
    val safeName = rawName.replace("/", "_")

    val attachmentsDir = FilePathManager(context).attachmentsDir

    val attachmentId = UUID.randomUUID().toString()
    val destination = File(attachmentsDir, attachmentId)
    return runCatching {
        val finalName: String

        if (type == AttachmentType.Image) {
            val inputStream = resolver.openInputStream(uri) ?: return@runCatching null
            val originalBytes = inputStream.use { input -> input.readBytes() }
            val compressedBytes = compressAttachmentImage(originalBytes)
            FileOutputStream(destination).use { output ->
                output.write(compressedBytes)
            }
            finalName = normalizedJpegAttachmentName(name ?: safeName)
        } else {
            val inputStream = resolver.openInputStream(uri) ?: return@runCatching null
            inputStream.use { input ->
                FileOutputStream(destination).use { output ->
                    input.copyTo(output)
                }
            }
            finalName = name ?: safeName
        }

        val finalSize = destination.length().takeIf { it > 0 } ?: size ?: 0L

        Attachment(
            id = attachmentId,
            name = finalName,
            sizeBytes = finalSize,
            type = type,
            localPath = destination.absolutePath,
            isUploading = false
        )
    }.getOrNull()
}

private fun normalizedJpegAttachmentName(name: String?): String {
    val raw = name
        ?.replace("\u0000", "")
        ?.replace("\\", "/")
        ?.substringAfterLast("/")
        ?.trim()
        ?.takeIf { it.isNotBlank() }
        ?: "image"
    val base = raw.substringBeforeLast(".", raw).ifBlank { "image" }
    return "$base.jpg"
}

private fun openAttachment(context: Context, attachment: Attachment) {
    val path = attachment.localPath
    if (path.isNullOrBlank()) {
        Toast.makeText(context, "Attachment not available", Toast.LENGTH_SHORT).show()
        return
    }
    val file = File(path)
    if (!file.exists()) {
        Toast.makeText(context, "Attachment not downloaded", Toast.LENGTH_SHORT).show()
        return
    }

    val extension = file.extension.lowercase()
    val mimeFromExtension = if (extension.isNotBlank()) {
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
    } else {
        null
    }
    val mime = when {
        attachment.type == AttachmentType.Image -> mimeFromExtension ?: "image/*"
        else -> mimeFromExtension ?: "*/*"
    }

    val uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        file
    )
    val intent = Intent(Intent.ACTION_VIEW)
        .setDataAndType(uri, mime)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    val chooser = Intent.createChooser(intent, "Open attachment")
    val resolved = intent.resolveActivity(context.packageManager)
    if (resolved != null) {
        context.startActivity(chooser)
    } else {
        Toast.makeText(context, "No app available to open this file", Toast.LENGTH_SHORT).show()
    }
}

private fun queryDisplayName(resolver: android.content.ContentResolver, uri: Uri): String? {
    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) {
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0) return cursor.getString(index)
        }
    }
    return null
}

private fun querySize(resolver: android.content.ContentResolver, uri: Uri): Long? {
    resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) {
            val index = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (index >= 0) return cursor.getLong(index)
        }
    }
    return null
}
