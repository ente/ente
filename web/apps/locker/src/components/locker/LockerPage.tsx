import { DeleteCollectionDialog } from "@/components/collections/DeleteCollectionDialog";
import { LockerCollectionShareDrawer } from "@/components/collections/LockerCollectionShareDrawer";
import { CreateItemDialog } from "@/components/create-item/CreateItemDialog";
import { ItemList } from "@/components/items/ItemList";
import { EmptyTrashDialog } from "@/components/locker/EmptyTrashDialog";
import { LockerDragOverlay } from "@/components/locker/LockerDragOverlay";
import { useCollectionActions } from "@/components/locker/use-collection-actions";
import { useItemActions } from "@/components/locker/use-item-actions";
import { useLockerConfirmation } from "@/components/locker/use-locker-confirmation";
import { useLockerData } from "@/components/locker/use-locker-data";
import { useLockerNavigation } from "@/components/locker/use-locker-navigation";
import { useLockerUploads } from "@/components/locker/use-locker-uploads";
import { useTrashActions } from "@/components/locker/use-trash-actions";
import { LockerNavbar } from "@/components/LockerNavbar";
import { LockerSidebar } from "@/components/sidebar/LockerSidebar";
import { LockerConfirmDialog } from "@/components/ui/LockerConfirmDialog";
import { useSetupLockerI18n } from "@/i18n/locker";
import { fetchCollectionSharees } from "@/services/collection-sharing";
import { lockerColorSx } from "@/styles/tokens";
import { PlusSignIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
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
    const [toast, setToast] = useState<string | null>(null);

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
        warmContacts,
    } = useLockerData({ router, logout, showMiniDialog });

    const {
        confirmDialog,
        visibleConfirmDialog,
        closeConfirmDialog,
        handleConfirmDialogConfirm,
        requestConfirmation,
    } = useLockerConfirmation();

    const {
        editItem,
        setEditItem,
        handleCreateItem,
        handleUpdateItem,
        handleDeleteItem,
        handleDeleteItems,
        handleEditItem,
    } = useItemActions({
        collections,
        masterKey,
        selectedCollectionID,
        refreshData,
        setToast,
        requestConfirmation,
    });

    const {
        deleteCollectionDialog,
        visibleDeleteCollectionDialog,
        setDeleteCollectionDialog,
        shareCollectionID,
        setShareCollectionID,
        handleCreateCollection,
        ensureCollectionsExist,
        handleRenameCollection,
        handleDeleteCollection,
        handleConfirmDeleteCollection,
        handleOpenShareCollection,
        handleShareCollection,
        handleUnshareCollection,
        handleLeaveCollection,
    } = useCollectionActions({
        collections,
        masterKey,
        selectedCollectionID,
        routerPathname: router.pathname,
        navigateHome,
        removeCollectionFromState,
        refreshData,
        setToast,
        requestConfirmation,
    });

    const {
        createDialogOpen,
        prefilledUploadItems,
        isDragActive,
        handleCreateDialogClose,
        openCreateDialog,
        handleUploadFileWithProgress,
        handleUploadsFinished,
        handleUploadItemComplete,
        handleDragEnter,
        handleDragOver,
        handleDragLeave,
        handleDrop,
    } = useLockerUploads({
        masterKey,
        ensureUploadLimitState,
        refreshData,
        setToast,
    });

    const {
        emptyTrashDialog,
        visibleEmptyTrashDialog,
        setEmptyTrashDialog,
        handlePermanentlyDelete,
        handleRestoreItem,
        handleEmptyTrash,
        handleConfirmEmptyTrash,
    } = useTrashActions({
        refreshData,
        requestConfirmation,
        setToast,
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
                onSelectCollections={handleSelectCollections}
                onSelectTrash={handleSelectTrash}
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
                warmContacts={warmContacts}
            />
            <LockerConfirmDialog
                open={confirmDialog !== null}
                illustration={visibleConfirmDialog?.illustration ?? ""}
                title={visibleConfirmDialog?.title ?? ""}
                body={visibleConfirmDialog?.body}
                confirmLabel={visibleConfirmDialog?.confirmLabel ?? ""}
                tone={visibleConfirmDialog?.tone}
                loading={visibleConfirmDialog?.loading}
                error={visibleConfirmDialog?.error}
                onClose={closeConfirmDialog}
                onConfirm={handleConfirmDialogConfirm}
            />
            <EmptyTrashDialog
                dialogState={emptyTrashDialog}
                visibleDialogState={visibleEmptyTrashDialog}
                onClose={() => setEmptyTrashDialog(null)}
                onConfirm={handleConfirmEmptyTrash}
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
                    sx={(theme) => ({
                        position: "fixed",
                        right: "max(16px, env(safe-area-inset-right))",
                        bottom: "max(16px, env(safe-area-inset-bottom))",
                        width: 56,
                        height: 56,
                        minHeight: 56,
                        ...lockerColorSx(theme, {
                            color: "specialWhite",
                            backgroundColor: "primary",
                        }),
                        boxShadow: "0px 8px 16px rgba(0, 0, 0, 0.08)",
                        zIndex: 1200,
                        "&:hover": {
                            ...lockerColorSx(theme, {
                                backgroundColor: "primaryDark",
                            }),
                            boxShadow: "0px 12px 24px rgba(0, 0, 0, 0.14)",
                        },
                    })}
                >
                    <HugeiconsIcon
                        icon={PlusSignIcon}
                        size={24}
                        strokeWidth={1.5}
                    />
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
