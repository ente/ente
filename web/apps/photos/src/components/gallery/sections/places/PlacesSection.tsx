import { CollectionMap } from "@/components/collections/CollectionMap";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import { useMemo, useState } from "react";
import { GallerySectionLayout } from "../../navigation/GallerySectionLayout";
import { homeDestination } from "../../navigation/navigation-state";
import { NavigationFrame } from "../../navigation/NavigationPrimitives";
import { usePhotosNavigation } from "../../navigation/PhotosNavigationContext";
import { albumFiles, albumView } from "../albums/album-files";
import type { GallerySectionProps } from "../types";
import { PlacesList } from "./PlacesList";

export const PlacesSection = ({
    library,
    operations,
    navigation,
    presentation,
}: GallerySectionProps) => {
    const files = useMemo(
        () => albumFiles(library, albumView(library, homeDestination)),
        [library],
    );
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
                        files={files}
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
                    files={files}
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
