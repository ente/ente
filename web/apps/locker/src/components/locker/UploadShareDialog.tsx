import { LockerFileLinkDialog } from "@/components/items/LockerFileLinkDialog";
import { useFileLink } from "@/components/items/use-file-link";
import { LockerConfirmDialog } from "@/components/ui/LockerConfirmDialog";
import type { LockerCollection } from "@/types";
import { canShareLockerFileLink, getItemTitle } from "@/types";
import { Button, Stack } from "@mui/material";
import { savedLocalUser } from "ente-accounts/services/accounts-db";
import { t } from "i18next";
import { useMemo } from "react";

interface UploadShareDialogProps {
    open: boolean;
    fileIDs: number[];
    collections: LockerCollection[];
    onClose: () => void;
    setFeedbackMessage: (message: string | null) => void;
}

export function UploadShareDialog({
    open,
    fileIDs,
    collections,
    onClose,
    setFeedbackMessage,
}: UploadShareDialogProps) {
    const currentUserID = savedLocalUser()?.id;
    const allItemsByID = useMemo(
        () =>
            new Map(
                collections
                    .flatMap((collection) => collection.items)
                    .map((item) => [item.id, item]),
            ),
        [collections],
    );
    const {
        activeFileLinkItem,
        activeFileLink,
        canNativeShare,
        isCreatingFileLink,
        isDeletingFileLink,
        isDeleteFileLinkConfirmOpen,
        setIsDeleteFileLinkConfirmOpen,
        closeFileLinkDialog,
        openFileLinkDialog,
        copyActiveFileLink,
        shareActiveFileLink,
        deleteActiveFileLink,
    } = useFileLink({ allItemsByID, currentUserID, setFeedbackMessage });
    const uploadedItems = fileIDs.flatMap((id) => {
        const item = allItemsByID.get(id);
        return item && canShareLockerFileLink(item, currentUserID)
            ? [item]
            : [];
    });
    const singleItem = fileIDs.length === 1 ? uploadedItems[0] : undefined;
    const handleShare = () => {
        if (singleItem) {
            onClose();
            void openFileLinkDialog(singleItem);
        }
    };
    return (
        <>
            <LockerConfirmDialog
                open={open}
                illustration="/images/onboarding-share.png"
                illustrationSize={180}
                compactIllustration
                title={t("uploadShareTitle", { count: fileIDs.length })}
                body={
                    singleItem ? (
                        t("uploadShareBody", { name: getItemTitle(singleItem) })
                    ) : fileIDs.length === 1 ? (
                        t("uploadShareSyncing")
                    ) : (
                        <>
                            {t("uploadShareChooseFile")}
                            <Stack sx={{ mt: 2, gap: 1 }}>
                                {uploadedItems.map((item) => (
                                    <Button
                                        key={item.id}
                                        fullWidth
                                        onClick={() => {
                                            onClose();
                                            void openFileLinkDialog(item);
                                        }}
                                    >
                                        {getItemTitle(item)}
                                    </Button>
                                ))}
                            </Stack>
                        </>
                    )
                }
                confirmLabel={
                    fileIDs.length === 1 ? t("uploadShareFile") : t("done")
                }
                confirmDisabled={fileIDs.length === 1 && !singleItem}
                cancelLabel={fileIDs.length === 1 ? t("done") : undefined}
                tone="primary"
                onClose={onClose}
                onConfirm={fileIDs.length === 1 ? handleShare : onClose}
            />
            <LockerFileLinkDialog
                open={activeFileLinkItem !== null}
                itemTitle={
                    activeFileLinkItem ? getItemTitle(activeFileLinkItem) : ""
                }
                url={activeFileLink?.url}
                loading={isCreatingFileLink}
                deleting={isDeletingFileLink}
                showShareAction={canNativeShare}
                onClose={closeFileLinkDialog}
                onCopy={() => void copyActiveFileLink()}
                onShare={() => void shareActiveFileLink()}
                onDelete={() => setIsDeleteFileLinkConfirmOpen(true)}
            />
            <LockerConfirmDialog
                open={isDeleteFileLinkConfirmOpen}
                illustration="/images/file_delete_icon.png"
                title={t("deleteShareLinkDialogTitle")}
                body={t("deleteShareLinkConfirmation")}
                confirmLabel={t("delete")}
                loading={isDeletingFileLink}
                onClose={() => {
                    if (!isDeletingFileLink)
                        setIsDeleteFileLinkConfirmOpen(false);
                }}
                onConfirm={() => void deleteActiveFileLink()}
            />
        </>
    );
}
