import { DownloadStatusNotifications } from "ente-gallery/components/DownloadStatusNotifications";
import type { ComponentProps } from "react";
import { usePhotosNavigation } from "../navigation/PhotosNavigationContext";

export const GalleryDownloadNotifications = (
    props: Omit<
        ComponentProps<typeof DownloadStatusNotifications>,
        "onShowCollectionSummary"
    >,
) => {
    const { showCollectionSummary } = usePhotosNavigation();
    return (
        <DownloadStatusNotifications
            {...props}
            onShowCollectionSummary={(id, isHidden) => {
                void showCollectionSummary(id, isHidden);
            }}
        />
    );
};
