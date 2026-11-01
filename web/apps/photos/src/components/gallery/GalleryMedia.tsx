import type { FileListHeaderOrFooter } from "@/components/FileList";
import { FileListWithViewer } from "@/components/FileListWithViewer";
import { externalLink } from "@/utils/link";
import { Typography } from "@mui/material";
import { useOperationSource } from "./hooks/use-operation-source";
import type { GalleryMediaSource } from "./section-types";

import { useMemo } from "react";
import { Trans } from "react-i18next";

import type { GallerySectionProps } from "./section-types";
export const GalleryMedia = ({
    library,
    operations,
    navigation,
    source,
    header,
}: Pick<GallerySectionProps, "library" | "operations" | "navigation"> & {
    source: GalleryMediaSource;
    header?: FileListHeaderOrFooter;
}) => {
    useOperationSource(source, operations.setMediaSource);
    const fileCollectionIDs = useMemo(
        () =>
            library.collectionFiles.reduce((result, file) => {
                const collectionIDs = result.get(file.id);
                if (collectionIDs) {
                    if (!collectionIDs.includes(file.collectionID)) {
                        collectionIDs.push(file.collectionID);
                    }
                } else {
                    result.set(file.id, [file.collectionID]);
                }
                return result;
            }, new Map<number, number[]>()),
        [library.collectionFiles],
    );

    const showAppDownloadFooter =
        library.collectionFiles.length < 30 && !navigation.isInSearchMode;
    const footer = useMemo(
        () => (showAppDownloadFooter ? createAppDownloadFooter() : undefined),
        [showAppDownloadFooter],
    );
    return (
        <FileListWithViewer
            {...operations}
            {...source}
            user={library.user}
            header={header}
            footer={footer}
            enableDownload
            enableSelect
            isInIncomingSharedCollection={source.activeCollectionSummary?.attributes.has(
                "sharedIncoming",
            )}
            isInHiddenSection={source.mode == "hidden-albums"}
            showEditLocationAction={operations.selected.ownCount > 0}
            favoriteFileIDs={library.favoriteFileIDs}
            collectionNameByID={library.collectionNameByID}
            fileNormalCollectionIDs={library.fileNormalCollectionIDs}
            fileCollectionIDs={fileCollectionIDs}
            hiddenCollectionIDs={library.hiddenCollectionIDs}
            pendingFavoriteUpdates={library.pendingFavoriteUpdates}
            pendingVisibilityUpdates={library.pendingVisibilityUpdates}
            collectionSummaries={library.normalCollectionSummaries}
            emailByUserID={library.emailByUserID}
            pendingFileIndex={navigation.pendingFileNavigation?.fileIndex}
            pendingFileSidebar={navigation.pendingFileNavigation?.sidebar}
            pendingHighlightCommentID={
                navigation.pendingFileNavigation?.commentID
            }
        />
    );
};
const createAppDownloadFooter = (): FileListHeaderOrFooter => ({
    component: (
        <Typography
            variant="small"
            sx={{
                alignSelf: "flex-end",
                marginInline: "auto",
                marginBlock: 0.75,
                textAlign: "center",
                color: "text.faint",
            }}
        >
            <Trans
                i18nKey="install_mobile_app"
                components={{
                    a: externalLink(
                        "https://play.google.com/store/apps/details?id=io.ente.photos",
                    ),
                    b: externalLink(
                        "https://apps.apple.com/in/app/ente-photos/id1542026904",
                    ),
                }}
            />
        </Typography>
    ),
    height: 90,
});
