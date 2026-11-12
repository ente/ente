import { LockerFileLinkDialog } from "@/components/items/LockerFileLinkDialog";
import { useFileLink } from "@/components/items/use-file-link";
import { LockerConfirmDialog } from "@/components/ui/LockerConfirmDialog";
import type { LockerCollection } from "@/types";
import { canShareLockerFileLink, getItemTitle } from "@/types";
import { savedLocalUser } from "ente-accounts/services/accounts-db";
import { t } from "i18next";
import { useEffect, useMemo } from "react";
import { retryUploadShareSync } from "./upload-share-sync";

interface UploadShareDialogProps {
    open: boolean;
    fileIDs: number[];
    collections: LockerCollection[];
    onClose: () => void;
    refreshData: () => Promise<void>;
    setFeedbackMessage: (message: string | null) => void;
}

export function UploadShareDialog({
    open,
    fileIDs,
    collections,
    onClose,
    refreshData,
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
    const candidate =
        fileIDs.length === 1 ? allItemsByID.get(fileIDs[0]!) : undefined;
    const singleItem =
        candidate && canShareLockerFileLink(candidate, currentUserID)
            ? candidate
            : undefined;
    const isWaitingForSync = open && fileIDs.length === 1 && !candidate;
    useEffect(() => {
        if (!isWaitingForSync) return;
        return retryUploadShareSync(refreshData);
    }, [isWaitingForSync, refreshData]);
    const handleShare = () => {
        if (singleItem) {
            onClose();
            void openFileLinkDialog(singleItem);
        }
    };
    return (
        <>
            <LockerConfirmDialog
                open={open && fileIDs.length === 1}
                illustration="/images/onboarding-share.png"
                illustrationSize={180}
                compactIllustration
                title={t("uploadComplete")}
                body={
                    singleItem
                        ? t("uploadShareBody", {
                              name: getItemTitle(singleItem),
                          })
                        : null
                }
                confirmLabel={t("share")}
                confirmDisabled={!singleItem}
                cancelLabel={t("done")}
                tone="primary"
                onClose={onClose}
                onConfirm={handleShare}
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
