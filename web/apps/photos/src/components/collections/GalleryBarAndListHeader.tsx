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
} from "@/components/gallery/AlbumsHeader";
import { PeopleHeader } from "@/components/gallery/PeopleHeader";
import type { GalleryBarMode } from "@/components/gallery/reducer";
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
import type { Person } from "ente-new/photos/services/ml/people";
import { t } from "i18next";
import React, { useCallback, useEffect, useState } from "react";
import { AlbumCastDialog } from "./AlbumCastDialog";
import {
    CollectionHeader,
    type CollectionHeaderProps,
} from "./CollectionHeader";

type GalleryBarAndListHeaderProps = {
    mode: GalleryBarMode;
    shouldHide: boolean;
    collectionSummary: CollectionSummary | undefined;
    albums: CollectionSummary[];
    activeCollection: Collection | undefined;
    activePerson: Person | undefined;
    people: Person[];
    setActiveCollectionID: (collectionID: number) => void;
    onSelectPerson: (personID: string) => void;
    onBackToPeople: () => void;
    setFileListHeader: (header: FileListHeaderOrFooter) => void;
    hasActiveFileSelection: boolean;
} & Pick<
    CollectionHeaderProps,
    | "isActiveCollectionDownloadInProgress"
    | "onRemotePull"
    | "onAddSaveGroup"
    | "onEditAlbumDetails"
    | "onShowMap"
    | "onCollectionSlideshow"
    | "onBackToAlbums"
> &
    Pick<
        CollectionShareProps,
        "user" | "emailByUserID" | "shareSuggestionEmails" | "setBlockingLoad"
    >;

export const GalleryBarAndListHeader: React.FC<
    GalleryBarAndListHeaderProps
> = ({
    shouldHide,
    mode,
    user,
    collectionSummary,
    albums,
    activeCollection,
    setActiveCollectionID,
    setBlockingLoad,
    people,
    onSelectPerson,
    isActiveCollectionDownloadInProgress,
    hasActiveFileSelection,
    activePerson,
    emailByUserID,
    shareSuggestionEmails,
    onRemotePull,
    onEditAlbumDetails,
    onAddSaveGroup,
    onShowMap,
    onCollectionSlideshow,
    setFileListHeader,
    onBackToAlbums,
    onBackToPeople,
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
        if (shouldHide || mode == "links") return;

        // Pseudo-collections need header actions despite having no Collection.
        const shouldRenderCollectionHeader =
            mode != "people" &&
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
                            onSelectAlbum={setActiveCollectionID}
                            onBack={onBackToAlbums}
                        />
                    )}
                    <CollectionHeader
                        {...{
                            activeCollection,
                            setActiveCollectionID,
                            isActiveCollectionDownloadInProgress,
                            onRemotePull,
                            onAddSaveGroup,
                            onShowMap,
                            onCollectionSlideshow,
                            onBackToAlbums,
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
            ) : mode != "people" && collectionSummary ? (
                <GalleryItemsHeaderAdapter>
                    <GalleryItemsSummary
                        name={collectionSummary.name}
                        fileCount={collectionSummary.fileCount}
                    />
                </GalleryItemsHeaderAdapter>
            ) : activePerson ? (
                <PeopleHeader
                    onBack={onBackToPeople}
                    person={activePerson}
                    people={people}
                    onSelectPerson={onSelectPerson}
                />
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
        shouldHide,
        mode,
        collectionSummary,
        albums,
        activeCollection,
        isActiveCollectionDownloadInProgress,
        activePerson,
        showCollectionShare,
        openCollectionShare,
        openCollectionManageLink,
        showCollectionCast,
        hasActiveFileSelection,
        onRemotePull,
        onAddSaveGroup,
        onShowMap,
        onCollectionSlideshow,
        onBackToAlbums,
        onBackToPeople,
        onEditAlbumDetails,
        albumDescription,
        descriptionHeight,
        // TODO: Cluster
        // This causes a loop since it is an array dep
        // people,
    ]);

    if (shouldHide) {
        return <></>;
    }

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
