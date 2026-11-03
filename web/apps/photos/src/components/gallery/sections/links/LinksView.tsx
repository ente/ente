import { visibleQuickLinks } from "@/utils/quick-links";
import type { LocalUser } from "ente-accounts/services/user";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import {
    PseudoCollectionID,
    sortCollectionSummaries,
    type CollectionSummary,
    type CollectionsSortBy,
} from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import { useMemo } from "react";
import type { RemotePullOpts } from "../..";
import {
    GallerySectionLayout,
    type GallerySectionPresentation,
} from "../../navigation/GallerySectionLayout";
import { AlbumsOverview } from "../albums/AlbumsOverview";
import { LinksNavigation } from "./LinksNavigation";
import { PublicLinkDetails } from "./PublicLinkDetails";

interface LinksViewProps {
    presentation: GallerySectionPresentation;
    onSearchQueryChange: (query: string) => void;
    onChangeSortBy: (sortBy: CollectionsSortBy) => void;
    user: LocalUser;
    collections: Collection[];
    collectionFiles: EnteFile[];
    collectionSummaries: ReadonlyMap<number, CollectionSummary>;
    hiddenCollectionIDs: ReadonlySet<number>;
    hiddenFileIDs: ReadonlySet<number>;
    tempDeletedFileIDs: ReadonlySet<number>;
    tempHiddenFileIDs: ReadonlySet<number>;
    uncategorizedCollectionSummaryID: number;
    selectedLinkID: number | undefined;
    searchQuery: string;
    sortBy: CollectionsSortBy;
    setBlockingLoad: (value: boolean) => void;
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
}

export const LinksView = ({
    presentation,
    onSearchQueryChange,
    onChangeSortBy,
    user,
    collections,
    collectionFiles,
    collectionSummaries,
    hiddenCollectionIDs,
    hiddenFileIDs,
    tempDeletedFileIDs,
    tempHiddenFileIDs,
    uncategorizedCollectionSummaryID,
    selectedLinkID,
    searchQuery,
    sortBy,
    setBlockingLoad,
    onRemotePull,
}: LinksViewProps) => {
    const links = useMemo(
        () => visibleQuickLinks(collections, user.id, hiddenCollectionIDs),
        [collections, user.id, hiddenCollectionIDs],
    );
    const selectedLink = links.find(({ id }) => id === selectedLinkID);
    const selectedLinkSummary =
        selectedLink && collectionSummaries.get(selectedLink.id);
    const selectedLinkFiles = useMemo(
        () =>
            selectedLinkID === undefined
                ? []
                : collectionFiles.filter(
                      ({ id, collectionID }) =>
                          collectionID === selectedLinkID &&
                          !hiddenFileIDs.has(id) &&
                          !tempDeletedFileIDs.has(id) &&
                          !tempHiddenFileIDs.has(id),
                  ),
        [
            selectedLinkID,
            collectionFiles,
            hiddenFileIDs,
            tempDeletedFileIDs,
            tempHiddenFileIDs,
        ],
    );
    const overviewLinks = useMemo(() => {
        const summaries = links.flatMap((link) => {
            const summary = collectionSummaries.get(link.id);
            return summary ? [summary] : [];
        });
        const query = searchQuery.trim().toLowerCase();
        return sortCollectionSummaries(summaries, sortBy)
            .sort((a, b) => b.sortPriority - a.sortPriority)
            .filter(
                (summary) =>
                    summary.id !== uncategorizedCollectionSummaryID &&
                    summary.id !== PseudoCollectionID.hiddenItems &&
                    summary.id !== PseudoCollectionID.archiveItems &&
                    summary.id !== PseudoCollectionID.trash &&
                    !summary.attributes.has("hideFromCollectionBar") &&
                    summary.name.toLowerCase().includes(query),
            );
    }, [
        links,
        collectionSummaries,
        searchQuery,
        sortBy,
        uncategorizedCollectionSummaryID,
    ]);

    const content = selectedLink ? (
        <PublicLinkDetails
            key={selectedLink.id}
            collection={selectedLink}
            fileCount={
                selectedLinkSummary?.fileCount ?? selectedLinkFiles.length
            }
            files={selectedLinkFiles}
            coverFile={selectedLinkSummary?.coverFile}
            user={user}
            setBlockingLoad={setBlockingLoad}
            onRemotePull={onRemotePull}
        />
    ) : (
        <AlbumsOverview
            albums={overviewLinks}
            title={t("links")}
            filter="links"
            searchQuery={searchQuery}
            sortBy={sortBy}
            onRemotePull={onRemotePull}
        />
    );
    return (
        <GallerySectionLayout
            presentation={presentation}
            navigation={
                <LinksNavigation
                    {...presentation}
                    collectionSummaries={overviewLinks}
                    selectedLinkID={selectedLink?.id}
                    searchQuery={searchQuery}
                    onSearchQueryChange={onSearchQueryChange}
                    collectionsSortBy={sortBy}
                    onChangeCollectionsSortBy={onChangeSortBy}
                />
            }
        >
            {content}
        </GallerySectionLayout>
    );
};
