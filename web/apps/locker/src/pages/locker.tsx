import { CreateItemDialog } from "@/components/CreateItemDialog";
import { ItemList } from "@/components/ItemList";
import { LockerCollectionShareDrawer } from "@/components/LockerCollectionShareDrawer";
import { LockerNavbar } from "@/components/LockerNavbar";
import { LockerSidebar } from "@/components/LockerSidebar";
import { DeleteCollectionDialog } from "@/components/lockerPage/DeleteCollectionDialog";
import { LockerDragOverlay } from "@/components/lockerPage/LockerDragOverlay";
import { useLockerActions } from "@/components/lockerPage/useLockerActions";
import { useLockerData } from "@/components/lockerPage/useLockerData";
import { useLockerNavigation } from "@/components/lockerPage/useLockerNavigation";
import { useSetupLockerI18n } from "@/i18n/locker";
import { fetchCollectionSharees } from "@/services/remote";
import AddIcon from "@mui/icons-material/Add";
import { Box, Button, Fab, Snackbar, Stack, Typography } from "@mui/material";
import { LoadingIndicator } from "ente-base/components/loaders";
import { useBaseContext } from "ente-base/context";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useCallback, useState } from "react";

export const LockerPage: React.FC = () => {
    const { logout, showMiniDialog } = useBaseContext();
    const router = useRouter();
    const isLockerI18nReady = useSetupLockerI18n();
    const [sidebarOpen, setSidebarOpen] = useState(false);
    const [searchTerm, setSearchTerm] = useState("");

    const closeSidebar = useCallback(() => {
        setSidebarOpen(false);
    }, []);

    const {
        handleNavigateBack,
        handleSelectCollection,
        handleSelectCollections,
        handleSelectTrash,
        isCollectionRoutePending,
        isCollectionsView,
        isHomeView,
        isTrashView,
        navigateHome,
        selectedCollectionID,
    } = useLockerNavigation({ router, onAfterNavigate: closeSidebar });

    const {
        collections,
        ensureUploadLimitState,
        hasFetched,
        initialLoadError,
        masterKey,
        refreshData,
        removeCollectionFromState,
        trashItems,
        trashLastUpdatedAt,
        userDetails,
    } = useLockerData({ router, logout, showMiniDialog });

    const {
        createDialogOpen,
        deleteCollectionDialog,
        editItem,
        ensureCollectionsExist,
        handleConfirmDeleteCollection,
        handleCreateCollection,
        handleCreateDialogClose,
        handleCreateItem,
        handleDeleteCollection,
        handleDeleteItem,
        handleDeleteItems,
        handleDragEnter,
        handleDragLeave,
        handleDragOver,
        handleDrop,
        handleEditItem,
        handleEmptyTrash,
        handleLeaveCollection,
        handleOpenShareCollection,
        handlePermanentlyDelete,
        handleRenameCollection,
        handleRestoreItem,
        handleShareCollection,
        handleUnshareCollection,
        handleUpdateItem,
        handleUploadFileWithProgress,
        handleUploadItemComplete,
        handleUploadsFinished,
        isDragActive,
        openCreateDialog,
        prefilledUploadItems,
        setDeleteCollectionDialog,
        setEditItem,
        setShareCollectionID,
        shareCollectionID,
        setToast,
        toast,
        visibleDeleteCollectionDialog,
    } = useLockerActions({
        collections,
        ensureUploadLimitState,
        masterKey,
        selectedCollectionID,
        routerPathname: router.pathname,
        refreshData,
        navigateHome,
        removeCollectionFromState,
        showMiniDialog,
        trashLastUpdatedAt,
    });

    const sharedCollection =
        shareCollectionID === null
            ? null
            : (collections.find(
                  (collection) => collection.id === shareCollectionID,
              ) ?? null);
    const isViewLoading =
        !hasFetched || !isLockerI18nReady || isCollectionRoutePending;

    if (isViewLoading) {
        return <LoadingIndicator />;
    }

    if (initialLoadError && collections.length === 0) {
        return (
            <Stack sx={{ height: "100dvh", overflow: "hidden" }}>
                <LockerNavbar
                    onOpenSidebar={() => setSidebarOpen(true)}
                    showMenuButton
                    searchTerm={searchTerm}
                    onSearchTermChange={setSearchTerm}
                />
                <Box
                    sx={{
                        flex: 1,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        px: 3,
                    }}
                >
                    <Stack
                        sx={{
                            width: "100%",
                            maxWidth: 480,
                            gap: 1.5,
                            alignItems: "center",
                            textAlign: "center",
                        }}
                    >
                        <Typography variant="h3">{t("error")}</Typography>
                        <Typography variant="body" sx={{ color: "text.muted" }}>
                            {initialLoadError}
                        </Typography>
                        <Button
                            variant="contained"
                            onClick={() => router.reload()}
                        >
                            {t("retry")}
                        </Button>
                    </Stack>
                </Box>
            </Stack>
        );
    }

    return (
        <Stack
            sx={{ height: "100dvh", overflow: "hidden", position: "relative" }}
            onDragEnter={handleDragEnter}
            onDragOver={handleDragOver}
            onDragLeave={handleDragLeave}
            onDrop={handleDrop}
        >
            <LockerNavbar
                onOpenSidebar={() => setSidebarOpen(true)}
                showMenuButton
                searchTerm={searchTerm}
                onSearchTermChange={setSearchTerm}
            />
            <Box
                sx={{
                    flex: 1,
                    minWidth: 0,
                    minHeight: 0,
                    display: "flex",
                    overflow: "hidden",
                }}
            >
                <ItemList
                    collections={collections}
                    masterKey={masterKey}
                    trashItems={isTrashView ? trashItems : undefined}
                    isTrashView={isTrashView}
                    isCollectionsView={isCollectionsView}
                    selectedCollectionID={selectedCollectionID}
                    onSelectCollection={handleSelectCollection}
                    onEditItem={handleEditItem}
                    onDeleteItem={handleDeleteItem}
                    onDeleteItems={handleDeleteItems}
                    onPermanentlyDelete={handlePermanentlyDelete}
                    onRestoreItem={handleRestoreItem}
                    onEmptyTrash={handleEmptyTrash}
                    onRenameCollection={handleRenameCollection}
                    onDeleteCollection={handleDeleteCollection}
                    onCreateCollection={handleCreateCollection}
                    onShareCollection={handleOpenShareCollection}
                    onLeaveCollection={handleLeaveCollection}
                    searchTerm={searchTerm}
                    onNavigateBack={handleNavigateBack}
                />
            </Box>
            <LockerSidebar
                open={sidebarOpen}
                onClose={closeSidebar}
                collections={collections}
                trashItemCount={trashItems.length}
                onSelectHome={() => handleSelectCollection(null)}
                onSelectCollections={handleSelectCollections}
                onSelectTrash={handleSelectTrash}
                isHomeView={isHomeView}
                isTrashView={isTrashView}
                isCollectionsView={isCollectionsView}
                userDetails={userDetails}
            />
            <LockerCollectionShareDrawer
                open={shareCollectionID !== null}
                collection={sharedCollection}
                onClose={() => setShareCollectionID(null)}
                onShareCollection={handleShareCollection}
                onUnshareCollection={handleUnshareCollection}
                onLeaveCollection={handleLeaveCollection}
                onRefreshSharees={fetchCollectionSharees}
            />
            <DeleteCollectionDialog
                dialogState={deleteCollectionDialog}
                visibleDialogState={visibleDeleteCollectionDialog}
                onClose={() => setDeleteCollectionDialog(null)}
                onConfirm={handleConfirmDeleteCollection}
                onToggleDeleteFromEverywhere={(checked) =>
                    setDeleteCollectionDialog((current) =>
                        current
                            ? { ...current, deleteFromEverywhere: checked }
                            : current,
                    )
                }
            />

            {!isTrashView && (
                <Fab
                    color="primary"
                    aria-label={t("saveToLocker")}
                    onClick={openCreateDialog}
                    sx={{
                        position: "fixed",
                        right: "max(24px, env(safe-area-inset-right))",
                        bottom: "max(24px, env(safe-area-inset-bottom))",
                        width: 72,
                        height: 72,
                        minHeight: 72,
                        color: "#FFFFFF",
                        background:
                            "linear-gradient(135deg, #1071FF 0%, #0056CC 100%)",
                        boxShadow: "0 16px 40px rgba(0, 66, 173, 0.32)",
                        zIndex: 1200,
                        "&:hover": {
                            background:
                                "linear-gradient(135deg, #1A7AFF 0%, #004DB8 100%)",
                            boxShadow: "0 18px 44px rgba(0, 66, 173, 0.36)",
                        },
                    }}
                >
                    <AddIcon sx={{ fontSize: 36 }} />
                </Fab>
            )}

            <CreateItemDialog
                open={createDialogOpen}
                onClose={handleCreateDialogClose}
                collections={collections}
                onSave={handleCreateItem}
                onUploadProgress={handleUploadFileWithProgress}
                onUploadItemComplete={handleUploadItemComplete}
                onUploadsFinished={handleUploadsFinished}
                onCreateCollection={handleCreateCollection}
                onEnsureCollections={ensureCollectionsExist}
                onEnsureUploadLimitState={ensureUploadLimitState}
                defaultCollectionID={selectedCollectionID}
                initialItems={prefilledUploadItems}
                userDetails={userDetails}
            />

            {editItem && (
                <CreateItemDialog
                    open={!!editItem}
                    onClose={() => setEditItem(null)}
                    collections={collections}
                    onSave={handleUpdateItem}
                    onCreateCollection={handleCreateCollection}
                    editItem={editItem}
                    userDetails={userDetails}
                />
            )}

            <Snackbar
                open={toast !== null}
                message={toast}
                autoHideDuration={3000}
                onClose={(_event, reason) => {
                    if (reason === "clickaway") {
                        return;
                    }
                    setToast(null);
                }}
            />
            {isDragActive && <LockerDragOverlay />}
        </Stack>
    );
};

export default LockerPage;
