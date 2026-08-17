// TODO: Audit this file
import { AllAlbums } from "@/components/Collections/AllAlbums";
import { AllPeople } from "@/components/Collections/AllPeople";
import {
    CollectionShare,
    type CollectionShareIntent,
    type CollectionShareProps,
} from "@/components/Collections/CollectionShare";
import type { FileListHeaderOrFooter } from "@/components/FileList";
import {
    GalleryBarImpl,
    type GalleryBarImplProps,
} from "@/components/gallery/BarImpl";
import { PeopleHeader } from "@/components/gallery/PeopleHeader";
import { sortPeople, type PeopleSortBy } from "@/utils/people-sort";
import { useModalVisibility } from "ente-base/components/utils/modal";
import {
    isSaveCancelled,
    isSaveComplete,
    type SaveGroup,
} from "ente-gallery/components/utils/save-groups";
import type { Collection } from "ente-media/collection";
import {
    GalleryItemsHeaderAdapter,
    GalleryItemsSummary,
} from "ente-new/photos/components/gallery/ListHeader";
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
        "onRemotePull" | "onAddSaveGroup" | "onEditAlbumDetails" | "onShowMap"
    > &
    Pick<
        CollectionShareProps,
        "user" | "emailByUserID" | "shareSuggestionEmails" | "setBlockingLoad"
    >;

// TODO: Move this back into the gallery once its responsibilities are split.
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
    onSelectPerson,
    allPeople,
    saveGroups,
    canCreateAlbum,
    hasActiveFileSelection,
    activePerson,
    emailByUserID,
    shareSuggestionEmails,
    onRemotePull,
    onEditAlbumDetails,
    onAddSaveGroup,
    onShowMap,
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

    const albumDescription =
        activeCollection?.pubMagicMetadata?.data.caption?.trim();
    const [descriptionHeight, setDescriptionHeight] = useState(0);

    useEffect(() => {
        if (shouldHide) return;

        const collectionSummary = toShowCollectionSummaries.get(
            activeCollectionID!,
        );
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
                    }}
                    collectionSummary={collectionSummary}
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
                    {...{ onSelectPerson, people }}
                />
            ) : (
                <></>
            ),
            height: 68 + (albumDescription ? descriptionHeight : 0),
        });
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [
        shouldHide,
        mode,
        toShowCollectionSummaries,
        activeCollection,
        activeCollectionID,
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
        onEditAlbumDetails,
        albumDescription,
        descriptionHeight,
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
                    (cs) =>
                        !cs.attributes.has("hideFromCollectionBar") &&
                        !cs.attributes.has("quickLink") &&
                        (mode != "albums" || !cs.attributes.has("archived")),
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
