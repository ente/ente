import type { FileListWithViewerProps } from "@/components/FileListWithViewer";
import type { UploadTypeSelectorIntent } from "ente-gallery/components/Upload";
import type { useSaveGroups } from "ente-gallery/components/utils/save-groups";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import type { PeopleState } from "ente-new/photos/services/ml/people";
import type { Dispatch, SetStateAction } from "react";
import type { useGalleryPreferences } from "../hooks/use-gallery-preferences";
import type { useSelectedFileOperations } from "../media/use-selected-file-operations";
import type { GallerySectionPresentation } from "../navigation/GallerySectionLayout";
import type { GalleryNavigationState } from "../navigation/navigation-state";
import type { GalleryAction, GalleryState } from "../reducer";

export type GalleryMediaSource = Pick<
    FileListWithViewerProps,
    | "mode"
    | "modePlus"
    | "files"
    | "activeCollectionID"
    | "activeCollectionSummary"
    | "activePersonID"
    | "disableGrouping"
> & { activeCollection?: Collection | undefined };

export type GallerySectionOperations = Pick<
    FileListWithViewerProps,
    | "onAddSaveGroup"
    | "onFileVisibilityUpdate"
    | "onMarkTempDeleted"
    | "onRemotePull"
    | "onVisualFeedback"
    | "onAddFileToCollection"
> & {
    onRemoteFilesPull: () => Promise<void>;
    dispatch: Dispatch<GalleryAction>;
    peopleState: PeopleState | undefined;
    mutations: Parameters<typeof useSelectedFileOperations>[0]["mutations"];
    selectionDisabled: boolean;
    onToggleFavorite: (file: EnteFile) => Promise<void>;
    onSendLink: (file: EnteFile) => Promise<void>;
    setBlockingLoad: Dispatch<SetStateAction<boolean>>;
    onUpload: (
        intent?: UploadTypeSelectorIntent,
        uploadTargetCollection?: Collection,
    ) => void;
    saveGroups: ReturnType<typeof useSaveGroups>["saveGroups"];
    setSectionActivity: Dispatch<
        SetStateAction<{ selection: boolean; drop: boolean }>
    >;
};

export interface GallerySectionProps {
    library: Readonly<GalleryState> & {
        isFirstLoad: boolean;
        searchIndexRevision: number;
        remotePullRevision: number;
    };
    operations: GallerySectionOperations;
    navigation: GalleryNavigationState & {
        retainPerson: (
            personID: string | undefined,
            extraVisiblePersonID: string | undefined,
        ) => void;
    };
    preferences: ReturnType<typeof useGalleryPreferences>;
    presentation: GallerySectionPresentation;
}
