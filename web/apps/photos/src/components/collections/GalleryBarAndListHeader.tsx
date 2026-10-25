// TODO: Audit this file
import {
    CollectionShare,
    type CollectionShareIntent,
    type CollectionShareProps,
} from "@/components/collections/CollectionShare";
import type { FileListHeaderOrFooter } from "@/components/FileList";
import { HiddenAlbumsHeader } from "@/components/gallery/HiddenAlbumsHeader";
import { PeopleHeader } from "@/components/gallery/PeopleHeader";
import type { GalleryBarMode } from "@/components/gallery/reducer";
import { useMediaQuery, useTheme } from "@mui/material";
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
    hiddenAlbums: CollectionSummary[];
    activeCollection: Collection | undefined;
    activePerson: Person | undefined;
    people: Person[];
    setActiveCollectionID: (collectionID: number) => void;
    onSelectPerson: (personID: string) => void;
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
    hiddenAlbums,
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
    const compact = useMediaQuery(useTheme().breakpoints.down("md"));

    useEffect(() => {
        if (shouldHide || mode == "links") return;

        if (
            mode == "hidden-albums" &&
            collectionSummary?.id == PseudoCollectionID.hiddenItems
        ) {
            setFileListHeader({
                component: (
                    <HiddenAlbumsHeader
                        albums={hiddenAlbums}
                        onSelectAlbum={setActiveCollectionID}
                        onBackToAlbums={onBackToAlbums}
                    />
                ),
                height: hiddenAlbums.length ? (compact ? 238 : 274) : 48,
            });
            return;
        }

        // Pseudo-collections need header actions despite having no Collection.
        const shouldRenderCollectionHeader =
            mode != "people" &&
            collectionSummary &&
            (activeCollection ||
                collectionSummary.id <= PseudoCollectionID.all);

        setFileListHeader({
            component: shouldRenderCollectionHeader ? (
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
                    onBackToHidden={
                        mode == "hidden-albums"
                            ? () =>
                                  setActiveCollectionID(
                                      PseudoCollectionID.hiddenItems,
                                  )
                            : undefined
                    }
                    onCollectionShare={openCollectionShare}
                    onCollectionManageLink={openCollectionManageLink}
                    onCollectionCast={showCollectionCast}
                    onEditAlbumDetails={onEditAlbumDetails}
                    hasActiveFileSelection={hasActiveFileSelection}
                    onDescriptionHeightChange={setDescriptionHeight}
                />
            ) : mode != "people" && collectionSummary ? (
                <GalleryItemsHeaderAdapter>
                    <GalleryItemsSummary
                        name={collectionSummary.name}
                        fileCount={collectionSummary.fileCount}
                    />
                </GalleryItemsHeaderAdapter>
            ) : activePerson ? (
                <PeopleHeader
                    person={activePerson}
                    people={people}
                    onSelectPerson={onSelectPerson}
                />
            ) : (
                <></>
            ),
            height: 72 + (albumDescription ? descriptionHeight : 0),
        });
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [
        shouldHide,
        mode,
        collectionSummary,
        hiddenAlbums,
        compact,
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
