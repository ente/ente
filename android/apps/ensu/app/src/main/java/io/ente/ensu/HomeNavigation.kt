package io.ente.ensu

import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DrawerState
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import io.ente.ensu.bindings.ConfigDefaults
import io.ente.ensu.chat.Attachment
import io.ente.ensu.chat.AttachmentType
import io.ente.ensu.chat.ChatView
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.device.isChatSupported
import io.ente.ensu.llm.ModelSettingsScreen
import io.ente.ensu.logging.LogViewerScreen
import io.ente.ensu.notes.NotesSettingsScreen
import io.ente.ensu.settings.AdvancedSettingsDataStore
import io.ente.ensu.settings.KnowledgeSettingsScreen
import io.ente.ensu.settings.SettingsScreen
import io.ente.ensu.settings.SystemPromptSettingsScreen

@Composable
internal fun HomeNavigation(
    appState: AppState,
    store: AppStore,
    logRepository: io.ente.ensu.logging.FileLogRepository,
    advancedSettingsDataStore: AdvancedSettingsDataStore,
    appVersion: String,
    configDefaults: ConfigDefaults,
    navController: NavHostController,
    drawerState: DrawerState,
    currentRoute: String,
    currentSession: io.ente.ensu.chat.ChatSession?,
    onSignIn: () -> Unit,
    onOpenDrawer: () -> Unit,
    onNewChat: () -> Unit,
    onShowLogShareDialog: () -> Unit,
    onAttachmentSelected: (AttachmentType) -> Unit,
    onOpenAttachment: (Attachment) -> Unit,
) {
    val navigate: (String) -> Unit = { route ->
        store.cancelNotificationNavigation()
        navController.navigate(route)
    }
    val goBack: () -> Unit = {
        store.cancelNotificationNavigation()
        navController.popBackStack()
    }

    Scaffold(
        containerColor = EnsuColor.backgroundBase(),
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = {
            when (currentRoute) {
                HomeRoute.Chat -> {
                    Column {
                        TopBar(
                            sessionTitle = currentSession?.title,
                            showBrand = appState.chat.messages.isEmpty(),
                            modelDownloadStatus = appState.chat.downloadStatus,
                            modelDownloadPercent = appState.chat.downloadPercent,
                            onOpenDrawer = onOpenDrawer,
                            onNewChat = onNewChat,
                        )
                        androidx.compose.material3.HorizontalDivider(color = EnsuColor.border())
                    }
                }
                HomeRoute.Logs -> {
                    LogsTopBar(
                        onBack = goBack,
                        onShare = onShowLogShareDialog,
                    )
                }
                HomeRoute.ModelSettings -> {
                    SimpleTopBar(title = "Model Settings", onBack = goBack)
                }
                HomeRoute.SystemPromptSettings -> {
                    SimpleTopBar(title = "System Prompt", onBack = goBack)
                }
                HomeRoute.Settings -> {
                    SimpleTopBar(title = "Settings", onBack = goBack)
                }
                HomeRoute.Notes,
                HomeRoute.NotesSetup -> {
                    SimpleTopBar(title = "Your Notes", onBack = goBack)
                }
                HomeRoute.Knowledge -> {
                    SimpleTopBar(title = "Ensu Packs", onBack = goBack)
                }
                else -> Unit
            }
        },
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            NavHost(
                navController = navController,
                startDestination = HomeRoute.Chat,
                modifier = Modifier.fillMaxSize(),
            ) {
                composable(
                    route = HomeRoute.Chat,
                    enterTransition = { forwardEnter() },
                    exitTransition = { forwardExit() },
                    popEnterTransition = { backEnter() },
                    popExitTransition = { backExit() },
                ) {
                    ChatView(
                        voiceController = store.voiceController,
                        onOpenVoiceInput = { value ->
                            store.openVoiceInput(
                                value.text,
                                value.selection.min,
                                value.selection.max,
                                value.composition != null,
                            )
                        },
                        onOpenPacks = { navigate(HomeRoute.Knowledge) },
                        onOpenNotes = { navigate(HomeRoute.NotesSetup) },
                        hasSeenSourceIntroduction = store.hasSeenSourceIntroduction(),
                        onCompleteSourceIntroduction = store::completeSourceIntroduction,
                        onRetrySources = store::retrySourceInventory,
                        chatState = appState.chat,
                        isDrawerOpen = drawerState.currentValue == DrawerValue.Open,
                        onMessageChange = store::updateMessageText,
                        onComposerSelection = store::updateComposerSelection,
                        onSend = store::sendMessage,
                        onStop = store::stopGeneration,
                        onCancelDownload = store::cancelDownload,
                        onAttachmentSelected = onAttachmentSelected,
                        onRemoveAttachment = store::removeAttachment,
                        onEditMessage = { message -> store.beginEditing(message.id) },
                        onRetryMessage = { message -> store.retryAssistantMessage(message.id) },
                        onCancelEdit = store::cancelEditing,
                        onBranchChange = store::updateBranchSelection,
                        onOpenAttachment = onOpenAttachment,
                        onStartDownload = { userInitiated ->
                            store.startModelDownload(userInitiated = userInitiated)
                        },
                        onDismissUnsupportedDeviceDialog = store::dismissUnsupportedDeviceDialog,
                        onOverflowTrim = store::confirmOverflowTrim,
                        onOverflowCancel = store::cancelOverflowDialog,
                    )
                }
                composable(
                    route = HomeRoute.Settings,
                    enterTransition = { forwardEnter() },
                    exitTransition = { forwardExit() },
                    popEnterTransition = { backEnter() },
                    popExitTransition = { backExit() },
                ) {
                    SettingsScreen(
                        buildVersion = appVersion,
                        isAdvancedUnlocked = appState.developerSettings.isAdvancedUnlocked,
                        onOpenLogs = { navigate(HomeRoute.Logs) },
                        onOpenKnowledge = { navigate(HomeRoute.Knowledge) },
                        onOpenNotes = { navigate(HomeRoute.Notes) },
                        onOpenModelSettings = { navigate(HomeRoute.ModelSettings) },
                        onOpenSystemPromptSettings = { navigate(HomeRoute.SystemPromptSettings) },
                        onUnlockAdvanced = {
                            store.unlockAdvancedSettings()
                            advancedSettingsDataStore.persistUnlockAdvancedSettings()
                        },
                        onSignIn = onSignIn,
                    )
                }
                listOf(HomeRoute.Notes, HomeRoute.NotesSetup).forEach { route ->
                    composable(
                        route = route,
                        enterTransition = { forwardEnter() },
                        exitTransition = { forwardExit() },
                        popEnterTransition = { backEnter() },
                        popExitTransition = { backExit() },
                    ) {
                        NotesSettingsScreen(
                            store.notesStore,
                            store::setPickerPending,
                            allowRemoval = route == HomeRoute.Notes,
                        )
                    }
                }
                composable(
                    route = HomeRoute.Knowledge,
                    enterTransition = { forwardEnter() },
                    exitTransition = { forwardExit() },
                    popEnterTransition = { backEnter() },
                    popExitTransition = { backExit() },
                ) {
                    KnowledgeSettingsScreen(
                        state = appState.knowledge,
                        packDownloadsAllowed = appState.chat.deviceCapability.isChatSupported(),
                        onDownloadOrUpdate = store::downloadOrUpdateKnowledgePack,
                        onCancel = store::cancelKnowledgePackDownload,
                        onSetEnabled = store::setKnowledgePackEnabled,
                    )
                }
                composable(
                    route = HomeRoute.Logs,
                    enterTransition = { forwardEnter() },
                    exitTransition = { forwardExit() },
                    popEnterTransition = { backEnter() },
                    popExitTransition = { backExit() },
                ) {
                    LogViewerScreen(logRepository = logRepository)
                }
                composable(
                    route = HomeRoute.ModelSettings,
                    enterTransition = { forwardEnter() },
                    exitTransition = { forwardExit() },
                    popEnterTransition = { backEnter() },
                    popExitTransition = { backExit() },
                ) {
                    ModelSettingsScreen(
                        totalMemoryBytes = appState.chat.deviceCapability.totalMemoryBytes,
                        state = appState.modelSettings,
                        onSave = { modelSettings ->
                            store.updateModelSettings(modelSettings)
                            advancedSettingsDataStore.persistModelSettings(modelSettings)
                        },
                        onReset = {
                            store.resetModelSettings()
                            advancedSettingsDataStore.persistResetModelSettings()
                        },
                    )
                }
                composable(
                    route = HomeRoute.SystemPromptSettings,
                    enterTransition = { forwardEnter() },
                    exitTransition = { forwardExit() },
                    popEnterTransition = { backEnter() },
                    popExitTransition = { backExit() },
                ) {
                    SystemPromptSettingsScreen(
                        defaultPromptBody = configDefaults.mobileSystemPromptBody,
                        datePlaceholder = configDefaults.systemPromptDatePlaceholder,
                        systemPrompt = appState.developerSettings.systemPrompt,
                        onSave = { value ->
                            val updated = appState.developerSettings.copy(systemPrompt = value)
                            store.updateDeveloperSettings(updated)
                            advancedSettingsDataStore.persistSystemPrompt(value)
                            goBack()
                        },
                        onReset = {
                            val updated = appState.developerSettings.copy(systemPrompt = "")
                            store.updateDeveloperSettings(updated)
                            advancedSettingsDataStore.persistSystemPrompt("")
                            goBack()
                        },
                    )
                }
            }
        }
    }
}

internal object HomeRoute {
    const val Chat = "chat"
    const val Settings = "settings"
    const val Logs = "logs"
    const val ModelSettings = "model-settings"
    const val SystemPromptSettings = "system-prompt-settings"
    const val Knowledge = "knowledge"
    const val Notes = "notes"
    const val NotesSetup = "notes-setup"
}

internal fun AnimatedContentTransitionScope<NavBackStackEntry>.forwardEnter() =
    slideInHorizontally(
        initialOffsetX = { it },
        animationSpec = tween(220),
    ) + fadeIn(animationSpec = tween(90))

internal fun AnimatedContentTransitionScope<NavBackStackEntry>.forwardExit() =
    slideOutHorizontally(
        targetOffsetX = { -it },
        animationSpec = tween(220),
    ) + fadeOut(animationSpec = tween(90))

internal fun AnimatedContentTransitionScope<NavBackStackEntry>.backEnter() =
    slideInHorizontally(
        initialOffsetX = { -it },
        animationSpec = tween(220),
    ) + fadeIn(animationSpec = tween(90))

internal fun AnimatedContentTransitionScope<NavBackStackEntry>.backExit() =
    slideOutHorizontally(
        targetOffsetX = { it },
        animationSpec = tween(220),
    ) + fadeOut(animationSpec = tween(90))
