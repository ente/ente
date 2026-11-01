import { CollectionMap } from "@/components/collections/CollectionMap";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import { useMemo, useState } from "react";
import { GallerySectionLayout } from "./GallerySectionLayout";
import { NavigationFrame } from "./NavigationPrimitives";
import { usePhotosNavigation } from "./PhotosNavigationContext";
import { PlacesList } from "./PlacesList";
import type { GallerySectionProps } from "./section-types";

export const PlacesSection = ({
    library,
    operations,
    navigation,
    presentation,
}: GallerySectionProps) => {
    const [query, setQuery] = useState("");
    const { selectPlace } = usePhotosNavigation();
    const mapFileSource = useMemo(
        () => ({
            collectionFiles: library.collectionFiles,
            favoriteFileIDs: library.favoriteFileIDs,
            hiddenFileIDs: library.hiddenFileIDs,
            archivedFileIDs: library.archivedFileIDs,
            tempDeletedFileIDs: library.tempDeletedFileIDs,
            tempHiddenFileIDs: library.tempHiddenFileIDs,
        }),
        [
            library.collectionFiles,
            library.favoriteFileIDs,
            library.hiddenFileIDs,
            library.archivedFileIDs,
            library.tempDeletedFileIDs,
            library.tempHiddenFileIDs,
        ],
    );
    const summary = library.normalCollectionSummaries.get(
        PseudoCollectionID.all,
    );
    return (
        <GallerySectionLayout
            presentation={presentation}
            fullBleed
            navigation={
                <NavigationFrame
                    title={t("search_places")}
                    actions={null}
                    searchPlaceholder={t("search_in_places")}
                    searchQuery={query}
                    setSearchQuery={setQuery}
                    mobileDrawerProps={presentation.mobileDrawerProps}
                >
                    <PlacesList
                        files={library.filteredFiles}
                        searchQuery={query}
                        selectedPlace={navigation.selectedPlace}
                        onSelectPlace={(place) => {
                            selectPlace(place);
                            presentation.mobileDrawerProps.onClose();
                        }}
                    />
                </NavigationFrame>
            }
        >
            {summary && (
                <CollectionMap
                    collectionSummary={summary}
                    files={library.filteredFiles}
                    selectedPlace={navigation.selectedPlace}
                    placeSelectionRevision={navigation.placeSelectionRevision}
                    mapFileSource={mapFileSource}
                    onRemotePull={operations.onRemotePull}
                    onAddSaveGroup={operations.onAddSaveGroup}
                    onMarkTempDeleted={operations.onMarkTempDeleted}
                    onAddFileToCollection={operations.onAddFileToCollection}
                    onRemoteFilesPull={operations.onRemoteFilesPull}
                    onVisualFeedback={operations.onVisualFeedback}
                    fileNormalCollectionIDs={library.fileNormalCollectionIDs}
                    collectionNameByID={library.collectionNameByID}
                    emailByUserID={library.emailByUserID}
                />
            )}
        </GallerySectionLayout>
    );
};
