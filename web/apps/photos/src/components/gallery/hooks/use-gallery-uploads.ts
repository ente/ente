import type { Upload } from "@/components/Upload";
import { uploadManager } from "@/services/upload-manager";
import type { UploadTypeSelectorIntent } from "ente-gallery/components/Upload";
import type { Collection } from "ente-media/collection";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import type { ComponentProps } from "react";
import { useCallback, useState } from "react";
import type { FileWithPath } from "react-dropzone";
type UploadInputs = Pick<
    ComponentProps<typeof Upload>,
    | "activeCollection"
    | "isFirstUpload"
    | "isInHiddenSection"
    | "onUploadFile"
    | "onShowSubscription"
    | "onRemotePull"
    | "onRemoteFilesPull"
    | "onOpenCollectionSelector"
    | "onCloseCollectionSelector"
    | "onShowSessionExpiredDialog"
    | "setLoading"
> & { user: ComponentProps<typeof Upload>["user"] | undefined };
export const useGalleryUploads = ({
    user,
    activeCollection,
    isFirstUpload,
    isInHiddenSection,
    onUploadFile,
    onShowSubscription,
    onRemotePull: remotePull,
    onRemoteFilesPull: remoteFilesPull,
    onOpenCollectionSelector: handleOpenCollectionSelector,
    onCloseCollectionSelector: handleCloseCollectionSelector,
    onShowSessionExpiredDialog: showSessionExpiredDialog,
    setLoading: setBlockingLoad,
}: UploadInputs) => {
    const { watchFolderView } = usePhotosAppContext();
    const [shouldDisableDropzone, setShouldDisableDropzone] = useState(false);
    const [dragAndDropFiles, setDragAndDropFiles] = useState<FileWithPath[]>(
        [],
    );
    const [uploadTypeSelectorView, setUploadTypeSelectorView] = useState(false);
    const [uploadTypeSelectorIntent, setUploadTypeSelectorIntent] =
        useState<UploadTypeSelectorIntent>("upload");
    const [uploadTargetCollection, setUploadTargetCollection] =
        useState<Collection>();
    const openUploader = useCallback(
        (intent?: UploadTypeSelectorIntent, target?: Collection) => {
            if (uploadManager.isUploadInProgress()) return;
            setUploadTargetCollection(target);
            setUploadTypeSelectorIntent(intent ?? "upload");
            setUploadTypeSelectorView(true);
        },
        [],
    );
    const closeUploadTypeSelector = () => {
        setUploadTypeSelectorView(false);
        setUploadTargetCollection(undefined);
    };
    const uploadProps: ComponentProps<typeof Upload> | undefined = user
        ? {
              user,
              dragAndDropFiles,
              uploadTypeSelectorIntent,
              uploadTypeSelectorView,
              isFirstUpload,
              activeCollection,
              uploadTargetCollection,
              closeUploadTypeSelector,
              setLoading: setBlockingLoad,
              setShouldDisableDropzone,
              onRemotePull: remotePull,
              onRemoteFilesPull: remoteFilesPull,
              onOpenCollectionSelector: handleOpenCollectionSelector,
              onCloseCollectionSelector: handleCloseCollectionSelector,
              onUploadFile,
              onShowSubscription,
              onShowSessionExpiredDialog: showSessionExpiredDialog,
              isInHiddenSection,
          }
        : undefined;
    const dropzoneProps = {
        message: watchFolderView ? t("watch_folder_dropzone_hint") : undefined,
        disabled: shouldDisableDropzone,
        onDrop: setDragAndDropFiles,
    };
    return { openUploader, uploadTypeSelectorView, uploadProps, dropzoneProps };
};
