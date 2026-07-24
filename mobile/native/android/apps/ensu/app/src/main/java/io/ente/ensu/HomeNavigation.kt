@file:OptIn(ExperimentalAnimationApi::class)

package io.ente.ensu

import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.ExperimentalAnimationApi
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DrawerState
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavHostController
import com.google.accompanist.navigation.animation.AnimatedNavHost
import com.google.accompanist.navigation.animation.composable
import io.ente.ensu.chat.ChatView
import io.ente.ensu.settings.AdvancedSettingsDataStore
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.chat.Attachment
import io.ente.ensu.chat.AttachmentType
import io.ente.ensu.bindings.ConfigDefaults
import io.ente.ensu.AppState
import io.ente.ensu.AppStore
import io.ente.ensu.llm.ModelSettingsScreen
import io.ente.ensu.logging.LogViewerScreen
import io.ente.ensu.settings.SettingsScreen
import io.ente.ensu.settings.SystemPromptSettingsScreen
import io.ente.ensu.settings.KnowledgeSettingsScreen
import io.ente.ensu.device.isChatSupported

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
    onOpenAttachment: (Attachment) -> Unit
) {
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
                            onNewChat = onNewChat
                        )
                        androidx.compose.material3.HorizontalDivider(color = EnsuColor.border())
                    }
                }
                HomeRoute.Logs -> {
                    LogsTopBar(
                        onBack = { navController.popBackStack() },
                        onShare = onShowLogShareDialog
                    )
                }
                HomeRoute.ModelSettings -> {
                    SimpleTopBar(title = "Model Settings") { navController.popBackStack() }
                }
                HomeRoute.SystemPromptSettings -> {
                    SimpleTopBar(title = "System Prompt") { navController.popBackStack() }
                }
                HomeRoute.Settings -> {
                    SimpleTopBar(title = "Settings") { navController.popBackStack() }
                }
                HomeRoute.Knowledge -> {
                    SimpleTopBar(title = "Ensu Packs") { navController.popBackStack() }
                }
                else -> Unit
            }
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            AnimatedNavHost(
                navController = navController,
                startDestination = HomeRoute.Chat,
                modifier = Modifier.fillMaxSize()
            ) {
                composable(
                    route = HomeRoute.Chat,
                    enterTransition = { forwardEnter() },
                    exitTransition = { forwardExit() },
                    popEnterTransition = { backEnter() },
                    popExitTransition = { backExit() }
                ) {
                    ChatView(
                        chatState = appState.chat,
                        modelDownloader = store.modelDownloader,
                        transcriber = store.transcriber,
                        isDrawerOpen = drawerState.currentValue == DrawerValue.Open,
                        onMessageChange = store::updateMessageText,
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
                        onOverflowCancel = store::cancelOverflowDialog
                    )
                }
                composable(
                    route = HomeRoute.Settings,
                    enterTransition = { forwardEnter() },
                    exitTransition = { forwardExit() },
                    popEnterTransition = { backEnter() },
                    popExitTransition = { backExit() }
                ) {
                    SettingsScreen(
                        buildVersion = appVersion,
                        isAdvancedUnlocked = appState.developerSettings.isAdvancedUnlocked,
                        onOpenLogs = { navController.navigate(HomeRoute.Logs) },
                        onOpenKnowledge = { navController.navigate(HomeRoute.Knowledge) },
                        onOpenModelSettings = { navController.navigate(HomeRoute.ModelSettings) },
                        onOpenSystemPromptSettings = { navController.navigate(HomeRoute.SystemPromptSettings) },
                        onUnlockAdvanced = {
                            store.unlockAdvancedSettings()
                            advancedSettingsDataStore.persistUnlockAdvancedSettings()
                        },
                        onSignIn = onSignIn
                    )
                }
                composable(
                    route = HomeRoute.Knowledge,
                    enterTransition = { forwardEnter() },
                    exitTransition = { forwardExit() },
                    popEnterTransition = { backEnter() },
                    popExitTransition = { backExit() }
                ) {
                    KnowledgeSettingsScreen(
                        state = appState.knowledge,
                        packDownloadsAllowed = appState.chat.deviceCapability.isChatSupported(),
                        onDownloadOrUpdate = store::downloadOrUpdateKnowledgePack,
                        onCancel = store::cancelKnowledgePackDownload,
                        onSetEnabled = store::setKnowledgePackEnabled
                    )
                }
                composable(
                    route = HomeRoute.Logs,
                    enterTransition = { forwardEnter() },
                    exitTransition = { forwardExit() },
                    popEnterTransition = { backEnter() },
                    popExitTransition = { backExit() }
                ) {
                    LogViewerScreen(
                        logRepository = logRepository
                    )
                }
                composable(
                    route = HomeRoute.ModelSettings,
                    enterTransition = { forwardEnter() },
                    exitTransition = { forwardExit() },
                    popEnterTransition = { backEnter() },
                    popExitTransition = { backExit() }
                ) {
                    ModelSettingsScreen(
                        defaults = configDefaults,
                        state = appState.modelSettings,
                        onSave = { modelSettings ->
                            store.updateModelSettings(modelSettings)
                            advancedSettingsDataStore.persistModelSettings(modelSettings)
                        },
                        onReset = {
                            store.resetModelSettings()
                            advancedSettingsDataStore.persistResetModelSettings()
                        }
                    )
                }
                composable(
                    route = HomeRoute.SystemPromptSettings,
                    enterTransition = { forwardEnter() },
                    exitTransition = { forwardExit() },
                    popEnterTransition = { backEnter() },
                    popExitTransition = { backExit() }
                ) {
                    SystemPromptSettingsScreen(
                        defaultPromptBody = configDefaults.mobileSystemPromptBody,
                        datePlaceholder = configDefaults.systemPromptDatePlaceholder,
                        systemPrompt = appState.developerSettings.systemPrompt,
                        onSave = { value ->
                            val updated = appState.developerSettings.copy(systemPrompt = value)
                            store.updateDeveloperSettings(updated)
                            advancedSettingsDataStore.persistSystemPrompt(value)
                            navController.popBackStack()
                        },
                        onReset = {
                            val updated = appState.developerSettings.copy(systemPrompt = "")
                            store.updateDeveloperSettings(updated)
                            advancedSettingsDataStore.persistSystemPrompt("")
                            navController.popBackStack()
                        }
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
}

internal fun AnimatedContentTransitionScope<NavBackStackEntry>.forwardEnter() =
    slideInHorizontally(
        initialOffsetX = { it },
        animationSpec = tween(220)
    ) + fadeIn(animationSpec = tween(90))

internal fun AnimatedContentTransitionScope<NavBackStackEntry>.forwardExit() =
    slideOutHorizontally(
        targetOffsetX = { -it },
        animationSpec = tween(220)
    ) + fadeOut(animationSpec = tween(90))

internal fun AnimatedContentTransitionScope<NavBackStackEntry>.backEnter() =
    slideInHorizontally(
        initialOffsetX = { -it },
        animationSpec = tween(220)
    ) + fadeIn(animationSpec = tween(90))

internal fun AnimatedContentTransitionScope<NavBackStackEntry>.backExit() =
    slideOutHorizontally(
        targetOffsetX = { it },
        animationSpec = tween(220)
    ) + fadeOut(animationSpec = tween(90))
