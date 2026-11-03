// TODO: Audit this file
import {
    CollectionShare,
    type CollectionShareIntent,
    type CollectionShareProps,
} from "@/components/collections/CollectionShare";
import type { FileListHeaderOrFooter } from "@/components/FileList";
import {
    AlbumsHeader,
    albumsHeaderHeight,
} from "@/components/gallery/sections/albums/AlbumsHeader";
import { Box } from "@mui/material";
import { useModalVisibility } from "ente-base/components/utils/modal";
import type { Collection } from "ente-media/collection";
import {
    GalleryItemsHeaderAdapter,
    GalleryItemsSummary,
} from "ente-new/photos/components/gallery/ListHeader";
import {
    PseudoCollectionID,
    type CollectionSummary,
} from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import React, { useCallback, useEffect, useState } from "react";
import { AlbumCastDialog } from "./AlbumCastDialog";
import {
    CollectionHeader,
    type CollectionHeaderProps,
} from "./CollectionHeader";

type AlbumContentHeaderProps = {
    collectionSummary: CollectionSummary | undefined;
    albums: CollectionSummary[];
    activeCollection: Collection | undefined;
    setFileListHeader: (header: FileListHeaderOrFooter) => void;
    hasActiveFileSelection: boolean;
} & Pick<
    CollectionHeaderProps,
    | "isActiveCollectionDownloadInProgress"
    | "onRemotePull"
    | "onAddSaveGroup"
    | "onEditAlbumDetails"
    | "onCollectionSlideshow"
    | "showBackToAlbums"
> &
    Pick<
        CollectionShareProps,
        "user" | "emailByUserID" | "shareSuggestionEmails" | "setBlockingLoad"
    >;

export const AlbumContentHeader: React.FC<AlbumContentHeaderProps> = ({
    user,
    collectionSummary,
    albums,
    activeCollection,
    setBlockingLoad,
    isActiveCollectionDownloadInProgress,
    hasActiveFileSelection,
    emailByUserID,
    shareSuggestionEmails,
    onRemotePull,
    onEditAlbumDetails,
    onAddSaveGroup,
    onCollectionSlideshow,
    setFileListHeader,
    showBackToAlbums,
}) => {
    const { show: showCollectionShare, props: collectionShareVisibilityProps } =
        useModalVisibility();
    const { show: showCollectionCast, props: collectionCastVisibilityProps } =
        useModalVisibility();
    const [collectionShareIntent, setCollectionShareIntent] =
        useState<CollectionShareIntent>();

    const openCollectionShare = useCallback(() => {
        setCollectionShareIntent(undefined);
        showCollectionShare();
    }, [showCollectionShare]);

    const openCollectionManageLink = useCallback(() => {
        setCollectionShareIntent("manage-link");
        showCollectionShare();
    }, [showCollectionShare]);

    const closeCollectionShare = useCallback(() => {
        setCollectionShareIntent(undefined);
        collectionShareVisibilityProps.onClose();
    }, [collectionShareVisibilityProps]);

    const albumDescription =
        activeCollection?.pubMagicMetadata?.data.caption?.trim();
    const [descriptionHeight, setDescriptionHeight] = useState(0);

    useEffect(() => {
        // Pseudo-collections need header actions despite having no Collection.
        const shouldRenderCollectionHeader =
            collectionSummary &&
            (activeCollection ||
                collectionSummary.id <= PseudoCollectionID.all);

        const showAlbums =
            collectionSummary?.type == "hiddenItems" ||
            collectionSummary?.type == "archiveItems";

        setFileListHeader({
            component: shouldRenderCollectionHeader ? (
                <Box sx={{ width: "100%" }}>
                    {showAlbums && (
                        <AlbumsHeader
                            title={t(
                                collectionSummary.type == "hiddenItems"
                                    ? "hidden_albums"
                                    : "section_archive",
                            )}
                            albums={albums}
                        />
                    )}
                    <CollectionHeader
                        {...{
                            activeCollection,
                            isActiveCollectionDownloadInProgress,
                            onRemotePull,
                            onAddSaveGroup,
                            onCollectionSlideshow,
                            showBackToAlbums,
                        }}
                        collectionSummary={collectionSummary}
                        onCollectionShare={openCollectionShare}
                        onCollectionManageLink={openCollectionManageLink}
                        onCollectionCast={showCollectionCast}
                        onEditAlbumDetails={onEditAlbumDetails}
                        hasActiveFileSelection={hasActiveFileSelection}
                        onDescriptionHeightChange={setDescriptionHeight}
                    />
                </Box>
            ) : collectionSummary ? (
                <GalleryItemsHeaderAdapter>
                    <GalleryItemsSummary
                        name={collectionSummary.name}
                        fileCount={collectionSummary.fileCount}
                    />
                </GalleryItemsHeaderAdapter>
            ) : (
                <></>
            ),
            height:
                72 +
                (showAlbums ? (albums.length ? albumsHeaderHeight : 78) : 0) +
                (albumDescription ? descriptionHeight : 0),
        });
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [
        collectionSummary,
        albums,
        activeCollection,
        isActiveCollectionDownloadInProgress,
        showCollectionShare,
        openCollectionShare,
        openCollectionManageLink,
        showCollectionCast,
        hasActiveFileSelection,
        onRemotePull,
        onAddSaveGroup,
        onCollectionSlideshow,
        showBackToAlbums,
        onEditAlbumDetails,
        albumDescription,
        descriptionHeight,
    ]);

    return (
        <>
            {activeCollection && (
                <>
                    <CollectionShare
                        {...collectionShareVisibilityProps}
                        onClose={closeCollectionShare}
                        collectionSummary={collectionSummary!}
                        collection={activeCollection}
                        intent={collectionShareIntent}
                        {...{
                            user,
                            emailByUserID,
                            shareSuggestionEmails,
                            setBlockingLoad,
                            onRemotePull,
                        }}
                    />
                    <AlbumCastDialog
                        {...collectionCastVisibilityProps}
                        collection={activeCollection}
                    />
                </>
            )}
        </>
    );
};
