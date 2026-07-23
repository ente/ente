// TODO: Audit this file
import { AllAlbums } from "@/components/Collections/AllAlbums";
import { AllPeople } from "@/components/Collections/AllPeople";
import {
    CollectionShare,
    type CollectionShareIntent,
    type CollectionShareProps,
} from "@/components/Collections/CollectionShare";
import type { FileListHeaderOrFooter } from "@/components/FileList";
import { useModalVisibility } from "ente-base/components/utils/modal";
import {
    isSaveCancelled,
    isSaveComplete,
    type SaveGroup,
} from "ente-gallery/components/utils/save-groups";
import type { Collection } from "ente-media/collection";
import {
    GalleryBarImpl,
    type GalleryBarImplProps,
} from "ente-new/photos/components/gallery/BarImpl";
import {
    GalleryItemsHeaderAdapter,
    GalleryItemsSummary,
} from "ente-new/photos/components/gallery/ListHeader";
import { PeopleHeader } from "ente-new/photos/components/gallery/PeopleHeader";
import {
    sortPeople,
    type PeopleSortBy,
} from "ente-new/photos/components/people-sort";
import {
    collectionsSortBy,
    haveOnlySystemCollections,
    PseudoCollectionID,
    sortCollectionSummaries,
    type CollectionsSortBy,
    type CollectionSummaries,
} from "ente-new/photos/services/collection-summary";
import type { Person } from "ente-new/photos/services/ml/people";
import { includes } from "ente-utils/type-guards";
import React, { useCallback, useEffect, useMemo, useState } from "react";
import { AlbumCastDialog } from "./AlbumCastDialog";
import {
    CollectionHeader,
    type CollectionHeaderProps,
} from "./CollectionHeader";

type GalleryBarAndListHeaderProps = Omit<
    GalleryBarImplProps,
    | "collectionSummaries"
    | "onSelectCollectionID"
    | "collectionsSortBy"
    | "onChangeCollectionsSortBy"
    | "peopleSortBy"
    | "onChangePeopleSortBy"
    | "onShowAllAlbums"
    | "onShowAllPeople"
> & {
    /**
     * When `true`, the bar is be hidden altogether.
     */
    shouldHide: boolean;
    barCollectionSummaries: CollectionSummaries;
    allPeople: Person[];
    activeCollection: Collection | undefined;
    setActiveCollectionID: (collectionID: number) => void;
    setFileListHeader: (header: FileListHeaderOrFooter) => void;
    hasActiveFileSelection: boolean;
    saveGroups: SaveGroup[];
    canCreateAlbum: boolean;
} & Pick<
        CollectionHeaderProps,
        | "files"
        | "mapFileSource"
        | "onRemotePull"
        | "onAddSaveGroup"
        | "onMarkTempDeleted"
        | "onAddFileToCollection"
        | "onRemoteFilesPull"
        | "onVisualFeedback"
        | "fileNormalCollectionIDs"
        | "collectionNameByID"
        | "onSelectCollection"
        | "onSelectPerson"
        | "canSetAlbumCover"
        | "onSetAlbumCover"
    > &
    Pick<
        CollectionShareProps,
        "user" | "emailByUserID" | "shareSuggestionEmails" | "setBlockingLoad"
    >;

/**
 * The gallery bar, the header for the list items, and state for any associated
 * dialogs that might be triggered by actions on either the bar or the header..
 *
 * This component manages the sticky horizontally scrollable bar shown at the
 * top of the gallery, AND the (non-sticky) header shown below the bar, at the
 * top of the actual list of items.
 *
 * These are disparate views - indeed, the list header is not even a child of
 * this component but is instead proxied via {@link setFileListHeader}. Still,
 * having this intermediate wrapper component allows us to move some of the
 * common concerns shared by both the gallery bar and list header (e.g. some
 * dialogs that can be invoked from both places) into this file instead of
 * cluttering the already big gallery component.
 *
 * TODO: Once the gallery code is better responsibilitied out, consider moving
 * this code back inline into the gallery.
 */
export const GalleryBarAndListHeader: React.FC<
    GalleryBarAndListHeaderProps
> = ({
    shouldHide,
    mode,
    onChangeMode,
    user,
    barCollectionSummaries: toShowCollectionSummaries,
    activeCollection,
    activeCollectionID,
    setActiveCollectionID,
    setBlockingLoad,
    people,
    allPeople,
    saveGroups,
    canCreateAlbum,
    hasActiveFileSelection,
    files,
    mapFileSource,
    activePerson,
    emailByUserID,
    shareSuggestionEmails,
    onRemotePull,
    canSetAlbumCover,
    onSetAlbumCover,
    onAddSaveGroup,
    onMarkTempDeleted,
    onAddFileToCollection,
    onRemoteFilesPull,
    onVisualFeedback,
    fileNormalCollectionIDs,
    collectionNameByID,
    onSelectCollection,
    onSelectPerson,
    setFileListHeader,
}) => {
    const { show: showAllAlbums, props: allAlbumsVisibilityProps } =
        useModalVisibility();
    const { show: showAllPeople, props: allPeopleVisibilityProps } =
        useModalVisibility();
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

    const [collectionsSortBy, setCollectionsSortBy] =
        useCollectionsSortByLocalState("updation-time-desc");
    const [peopleSortBy, setPeopleSortBy] =
        useState<PeopleSortBy>("count-desc");

    const shouldBeHidden = useMemo(
        () =>
            shouldHide ||
            (haveOnlySystemCollections(toShowCollectionSummaries) &&
                activeCollectionID === PseudoCollectionID.all),
        [shouldHide, toShowCollectionSummaries, activeCollectionID],
    );

    const sortedCollectionSummaries = useMemo(
        () =>
            sortCollectionSummaries(
                [...toShowCollectionSummaries.values()],
                collectionsSortBy,
            ).sort((a, b) => b.sortPriority - a.sortPriority),
        [collectionsSortBy, toShowCollectionSummaries],
    );
    const sortedPeople = useMemo(
        () => sortPeople(people, peopleSortBy),
        [people, peopleSortBy],
    );

    const isActiveCollectionDownloadInProgress = useCallback(() => {
        const group = saveGroups.find(
            (g) => g.collectionSummaryID === activeCollectionID,
        );
        return !!group && !isSaveComplete(group) && !isSaveCancelled(group);
    }, [saveGroups, activeCollectionID]);

    useEffect(() => {
        if (shouldHide) return;

        const collectionSummary = toShowCollectionSummaries.get(
            activeCollectionID!,
        );
        // Render the full CollectionHeader for pseudo-collections (e.g. trash)
        // so header actions/menus are available even without a real collection.
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
                        files,
                        mapFileSource,
                        setActiveCollectionID,
                        isActiveCollectionDownloadInProgress,
                        onRemotePull,
                        onAddSaveGroup,
                        onMarkTempDeleted,
                        onAddFileToCollection,
                        onRemoteFilesPull,
                        onVisualFeedback,
                        fileNormalCollectionIDs,
                        collectionNameByID,
                        emailByUserID,
                        onSelectCollection,
                        onSelectPerson,
                    }}
                    collectionSummary={collectionSummary}
                    onCollectionShare={openCollectionShare}
                    onCollectionManageLink={openCollectionManageLink}
                    onCollectionCast={showCollectionCast}
                    canSetAlbumCover={canSetAlbumCover}
                    onSetAlbumCover={onSetAlbumCover}
                    hasActiveFileSelection={hasActiveFileSelection}
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
                    {...{ onSelectPerson, people }}
                />
            ) : (
                <></>
            ),
            height: 68,
        });
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [
        shouldHide,
        mode,
        toShowCollectionSummaries,
        activeCollection,
        activeCollectionID,
        isActiveCollectionDownloadInProgress,
        files,
        mapFileSource,
        activePerson,
        showCollectionShare,
        openCollectionShare,
        openCollectionManageLink,
        showCollectionCast,
        hasActiveFileSelection,
        onRemotePull,
        onAddSaveGroup,
        onMarkTempDeleted,
        onAddFileToCollection,
        onRemoteFilesPull,
        onVisualFeedback,
        fileNormalCollectionIDs,
        collectionNameByID,
        emailByUserID,
        onSelectCollection,
        onSelectPerson,
        canSetAlbumCover,
        onSetAlbumCover,
        // TODO: Cluster
        // This causes a loop since it is an array dep
        // people,
    ]);

    if (shouldBeHidden) {
        return <></>;
    }

    return (
        <>
            <GalleryBarImpl
                {...{
                    mode,
                    onChangeMode,
                    activeCollectionID,
                    people: sortedPeople,
                    activePerson,
                    onSelectPerson,
                    collectionsSortBy,
                    peopleSortBy,
                }}
                onSelectCollectionID={setActiveCollectionID}
                onChangeCollectionsSortBy={setCollectionsSortBy}
                onChangePeopleSortBy={setPeopleSortBy}
                onShowAllAlbums={showAllAlbums}
                onShowAllPeople={showAllPeople}
                collectionSummaries={sortedCollectionSummaries.filter(
                    (cs) => !cs.attributes.has("hideFromCollectionBar"),
                )}
            />

            <AllAlbums
                {...allAlbumsVisibilityProps}
                collectionSummaries={sortedCollectionSummaries.filter(
                    (cs) => !cs.attributes.has("system"),
                )}
                onSelectCollectionID={setActiveCollectionID}
                onChangeCollectionsSortBy={setCollectionsSortBy}
                collectionsSortBy={collectionsSortBy}
                isInHiddenSection={mode == "hidden-albums"}
                canCreateAlbum={canCreateAlbum}
                onRemotePull={onRemotePull}
            />
            <AllPeople
                {...allPeopleVisibilityProps}
                people={sortedPeople}
                allPeople={allPeople}
                onSelectPerson={onSelectPerson}
                peopleSortBy={peopleSortBy}
                onChangePeopleSortBy={setPeopleSortBy}
            />
            {activeCollection && (
                <>
                    <CollectionShare
                        {...collectionShareVisibilityProps}
                        onClose={closeCollectionShare}
                        collectionSummary={
                            toShowCollectionSummaries.get(activeCollectionID!)!
                        }
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

/**
 * A hook that maintains the collections sort order both as in-memory and local
 * storage state.
 */
const useCollectionsSortByLocalState = (initialValue: CollectionsSortBy) => {
    const key = "collectionsSortBy";

    const [value, setValue] = useState(initialValue);

    useEffect(() => {
        const value = localStorage.getItem(key);
        if (value && includes(collectionsSortBy, value)) setValue(value);
    }, []);

    const setter = (value: CollectionsSortBy) => {
        localStorage.setItem(key, value);
        setValue(value);
    };

    return [value, setter] as const;
};
