import { LinksView } from "./LinksView";
import type { GallerySectionProps } from "./section-types";

export const LinksSection = ({
    library,
    operations,
    navigation,
    preferences,
    presentation,
}: GallerySectionProps) => {
    const selectedLinkID = navigation.destination.collectionID;
    return (
        <LinksView
            {...{ presentation, selectedLinkID }}
            user={library.user!}
            collections={library.collections}
            collectionFiles={library.collectionFiles}
            collectionSummaries={library.normalCollectionSummaries}
            hiddenCollectionIDs={library.hiddenCollectionIDs}
            hiddenFileIDs={library.hiddenFileIDs}
            tempDeletedFileIDs={library.tempDeletedFileIDs}
            tempHiddenFileIDs={library.tempHiddenFileIDs}
            uncategorizedCollectionSummaryID={
                library.uncategorizedCollectionSummaryID
            }
            searchQuery={preferences.albumSearchQuery}
            onSearchQueryChange={preferences.setAlbumSearchQuery}
            sortBy={preferences.collectionsSortBy}
            onChangeSortBy={preferences.onChangeCollectionsSortBy}
            onCreateAlbum={operations.onCreateAlbum}
            setBlockingLoad={operations.setBlockingLoad}
            onRemotePull={operations.onRemotePull}
        />
    );
};
