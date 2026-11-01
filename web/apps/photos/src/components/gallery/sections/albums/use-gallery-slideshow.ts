import { slideshowFiles } from "@/components/collections/album-slideshow";
import type { LocalUser } from "ente-accounts/services/user";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import { useCallback, useEffect, useState } from "react";

export const useGallerySlideshow = ({
    activeCollection,
    activeCollectionFiles,
    activeCollectionSummary,
    isInSearchMode,
    user,
}: {
    activeCollection: Collection | undefined;
    activeCollectionFiles: EnteFile[];
    activeCollectionSummary: CollectionSummary | undefined;
    isInSearchMode: boolean;
    user: LocalUser | undefined;
}) => {
    const { showNotification } = usePhotosAppContext();

    const [slideshow, setSlideshow] = useState<{
        files: EnteFile[];
        title: string;
        collectionID: number;
    }>();
    const closeSlideshow = useCallback(() => setSlideshow(undefined), []);

    const startSlideshow = useCallback(() => {
        if (!activeCollection) return;
        const files = slideshowFiles(activeCollectionFiles);
        if (!files.length) {
            showNotification({
                color: "primary",
                title: t("no_photos_found_here"),
            });
            return;
        }
        setSlideshow({
            files,
            title: activeCollectionSummary?.name ?? activeCollection.name,
            collectionID: activeCollection.id,
        });
    }, [
        activeCollection,
        activeCollectionFiles,
        activeCollectionSummary?.name,
        showNotification,
    ]);

    useEffect(() => {
        if (
            slideshow &&
            (slideshow.collectionID !== activeCollection?.id ||
                isInSearchMode ||
                !user)
        )
            closeSlideshow();
    }, [slideshow, activeCollection?.id, isInSearchMode, user, closeSlideshow]);

    return { slideshow, startSlideshow, closeSlideshow };
};
