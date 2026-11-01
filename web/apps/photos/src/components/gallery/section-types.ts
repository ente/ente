import type { FileListWithViewerProps } from "@/components/FileListWithViewer";
import type { UploadTypeSelectorIntent } from "ente-gallery/components/Upload";
import type { useSaveGroups } from "ente-gallery/components/utils/save-groups";
import type { EnteFile } from "ente-media/file";
import type { Dispatch, SetStateAction } from "react";
import type { GallerySectionPresentation } from "./GallerySectionLayout";
import type { PlaceSelection } from "./PlacesList";
import type { useGalleryPreferences } from "./hooks/use-gallery-preferences";
import type { GalleryState } from "./reducer";

export type GallerySectionOperations = Pick<
    FileListWithViewerProps,
    | "selected"
    | "setSelected"
    | "onContextMenuAction"
    | "onContextMenuOpenChange"
    | "suppressSelectionUI"
    | "showAddPersonAction"
    | "onAddSaveGroup"
    | "onFileVisibilityUpdate"
    | "onMarkTempDeleted"
    | "onSetOpenFileViewer"
    | "onRemotePull"
    | "onRemoteFilesPull"
    | "onVisualFeedback"
    | "onAddFileToCollection"
    | "onPendingNavigationConsumed"
> & {
    onToggleFavorite: (file: EnteFile) => Promise<void>;
    onSendLink: (file: EnteFile) => Promise<void>;
    setBlockingLoad: Dispatch<SetStateAction<boolean>>;
    onUpload: (intent?: UploadTypeSelectorIntent) => void;
    onCreateAlbum: () => void;
    saveGroups: ReturnType<typeof useSaveGroups>["saveGroups"];
    setSectionActivity: Dispatch<
        SetStateAction<{ selection: boolean; drop: boolean }>
    >;
};

export interface GallerySectionProps {
    library: Readonly<GalleryState> & { isFirstLoad: boolean };
    operations: GallerySectionOperations;
    navigation: {
        view: GalleryState["view"];
        isInSearchMode: boolean;
        isMapView: boolean;
        selectedPlace: PlaceSelection | undefined;
        placeSelectionRevision: number;
        pendingFileNavigation:
            | {
                  fileIndex: number;
                  sidebar?: FileListWithViewerProps["pendingFileSidebar"];
                  commentID?: string;
              }
            | undefined;
    };
    preferences: ReturnType<typeof useGalleryPreferences>;
    presentation: GallerySectionPresentation;
}
