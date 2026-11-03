import type { RemotePullOpts } from "@/components/gallery";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import {
    createAlbum,
    createHiddenAlbum,
} from "ente-new/photos/services/collection";
import { t } from "i18next";
import type React from "react";

interface CreateAlbumDialogProps extends ModalVisibilityProps {
    isHidden: boolean;
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
    onSelectCollectionID: (id: number) => void;
}

export const CreateAlbumDialog: React.FC<CreateAlbumDialogProps> = ({
    open,
    onClose,
    isHidden,
    onRemotePull,
    onSelectCollectionID,
}) => {
    const handleCreateAlbum = async (albumName: string) => {
        const newAlbum = isHidden
            ? await createHiddenAlbum(albumName)
            : await createAlbum(albumName);
        await onRemotePull();
        onSelectCollectionID(newAlbum.id);
    };

    return (
        <SingleInputDialog
            {...{ open, onClose }}
            title={t("new_album")}
            label={t("album_name")}
            submitButtonTitle={t("create")}
            onSubmit={handleCreateAlbum}
        />
    );
};
