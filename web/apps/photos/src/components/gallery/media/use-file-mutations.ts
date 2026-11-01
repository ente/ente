import type { FileOp } from "@/components/SelectedFileOptions";
import { errorDialogAttributes } from "ente-base/components/utils/dialog";
import { useBaseContext } from "ente-base/context";
import { isHTTPErrorWithStatus } from "ente-base/http";
import log from "ente-base/log";
import {
    quickLinkNameForFiles,
    resolveQuickLinkURL,
} from "ente-gallery/utils/quick-link";
import type { EnteFile } from "ente-media/file";
import { ItemVisibility, metadataHash } from "ente-media/file-metadata";
import { useSettingsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import {
    addToCollection,
    addToFavoritesCollection,
    createPublicURL,
    createQuickLinkCollection,
    removeFromFavoritesCollection,
} from "ente-new/photos/services/collection";
import { updateFilesVisibility } from "ente-new/photos/services/file";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import type { Dispatch } from "react";
import { useCallback, useState } from "react";
import type { RemotePullOpts } from "..";
import type { GalleryAction, GalleryState } from "../reducer";
export const useFileMutations = ({
    state,
    dispatch,
    remotePull,
    quickLinkVisibility,
}: {
    state: GalleryState;
    dispatch: Dispatch<GalleryAction>;
    remotePull: (opts?: RemotePullOpts) => Promise<void>;
    quickLinkVisibility: ItemVisibility;
}) => {
    const { user, favoriteFileIDs } = state;
    const { customDomain } = useSettingsSnapshot();
    const { showMiniDialog, onGenericError } = useBaseContext();
    const { showLoadingBar, hideLoadingBar } = usePhotosAppContext();
    const [publicLinkToast, setPublicLinkToast] = useState<{
        open: boolean;
        url?: string;
    }>({ open: false });
    const handleFavoriteFileOp = async (
        op: Extract<FileOp, "favorite" | "unfavorite">,
        selectedFiles: EnteFile[],
    ) => {
        const filesToProcess: EnteFile[] = [];
        let skippedUnsupportedSharedFile = false;

        // Shared copies need a metadata hash to find their owned equivalent.
        for (const file of selectedFiles) {
            if (file.ownerID == user!.id || metadataHash(file.metadata)) {
                filesToProcess.push(file);
            } else {
                skippedUnsupportedSharedFile = true;
            }
        }

        if (!filesToProcess.length) {
            return { processed: false, skippedUnsupportedSharedFile };
        }

        const isFavorite = op == "favorite";
        const previousFavoriteByFileID = new Map(
            filesToProcess.map((file) => [
                file.id,
                favoriteFileIDs.has(file.id),
            ]),
        );

        for (const file of filesToProcess) {
            dispatch({ type: "addPendingFavoriteUpdate", fileID: file.id });
            dispatch({ type: "unsyncedFavoriteUpdate", file, isFavorite });
        }

        try {
            const action = isFavorite
                ? addToFavoritesCollection
                : removeFromFavoritesCollection;
            await action(filesToProcess);
            return { processed: true, skippedUnsupportedSharedFile };
        } catch (e) {
            for (const file of filesToProcess) {
                dispatch({
                    type: "unsyncedFavoriteUpdate",
                    file,
                    isFavorite: previousFavoriteByFileID.get(file.id)!,
                });
            }
            throw e;
        } finally {
            for (const file of filesToProcess) {
                dispatch({
                    type: "removePendingFavoriteUpdate",
                    fileID: file.id,
                });
            }
        }
    };
    const onSendLinkError = useCallback(
        (e: unknown) => {
            if (isHTTPErrorWithStatus(e, 402)) {
                log.error("Could not create share link", e);
                showMiniDialog(
                    errorDialogAttributes(
                        t("share_link_subscription_required"),
                    ),
                );
            } else {
                onGenericError(e);
            }
        },
        [showMiniDialog, onGenericError],
    );
    const handleFileViewerToggleFavorite = useCallback(
        async (file: EnteFile) => {
            const fileID = file.id;
            const isFavorite = favoriteFileIDs.has(fileID);

            dispatch({ type: "addPendingFavoriteUpdate", fileID });
            dispatch({
                type: "unsyncedFavoriteUpdate",
                file,
                isFavorite: !isFavorite,
            });
            try {
                const action = isFavorite
                    ? removeFromFavoritesCollection
                    : addToFavoritesCollection;
                await action([file]);
            } catch (e) {
                dispatch({ type: "unsyncedFavoriteUpdate", file, isFavorite });
                throw e;
            } finally {
                dispatch({ type: "removePendingFavoriteUpdate", fileID });
            }
        },
        [favoriteFileIDs],
    );
    const handleFileViewerFileVisibilityUpdate = useCallback(
        async (file: EnteFile, visibility: ItemVisibility) => {
            const fileID = file.id;
            dispatch({ type: "addPendingVisibilityUpdate", fileID });
            try {
                await updateFilesVisibility([file], visibility);
                // Keep the UI ahead of the background pull.
                // TODO: Replace with files pull?
                dispatch({
                    type: "unsyncedPrivateMagicMetadataUpdate",
                    fileID,
                    privateMagicMetadata: {
                        ...file.magicMetadata,
                        count: file.magicMetadata?.count ?? 0,
                        version: (file.magicMetadata?.version ?? 0) + 1,
                        data: { ...file.magicMetadata?.data, visibility },
                    },
                });
            } finally {
                dispatch({ type: "removePendingVisibilityUpdate", fileID });
            }
        },
        [],
    );
    const handleFileViewerSendLink = useCallback(
        async (file: EnteFile) => {
            if (file.ownerID != user?.id) return;

            showLoadingBar();
            try {
                const quickLinkCollection = await createQuickLinkCollection(
                    quickLinkNameForFiles([file]),
                    quickLinkVisibility,
                );
                await addToCollection(quickLinkCollection, [file]);
                const publicURL = await createPublicURL(
                    quickLinkCollection.id,
                    { enableJoin: false },
                );
                const resolvedURL = await resolveQuickLinkURL(
                    publicURL.url,
                    quickLinkCollection.key,
                    customDomain,
                );
                setPublicLinkToast({ open: true, url: resolvedURL });
                await remotePull({ silent: true, source: "viewer-send-link" });
            } catch (e) {
                onSendLinkError(e);
            } finally {
                hideLoadingBar();
            }
        },
        [
            user?.id,
            showLoadingBar,
            hideLoadingBar,
            customDomain,
            quickLinkVisibility,
            remotePull,
            onSendLinkError,
        ],
    );
    const handleMarkTempDeleted = useCallback(
        (files: EnteFile[]) => dispatch({ type: "markTempDeleted", files }),
        [],
    );
    return {
        publicLinkToast,
        setPublicLinkToast,
        handleFavoriteFileOp,
        onSendLinkError,
        handleFileViewerToggleFavorite,
        handleFileViewerFileVisibilityUpdate,
        handleFileViewerSendLink,
        handleMarkTempDeleted,
    };
};
