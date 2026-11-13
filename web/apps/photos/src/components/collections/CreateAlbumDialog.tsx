import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import type { Collection } from "ente-media/collection";
import {
    createAlbum,
    createHiddenAlbum,
    renameCollection,
} from "ente-new/photos/services/collection";
import { t } from "i18next";
import { useLayoutEffect, useRef, type FC } from "react";

interface CreateAlbumDialogProps extends ModalVisibilityProps {
    isHidden: boolean;
    onRemoteFilesPull: () => Promise<void>;
    onSelectCollectionID: (id: number) => void;
}

export const CreateAlbumDialog: FC<CreateAlbumDialogProps> = ({
    open,
    onClose,
    isHidden,
    onRemoteFilesPull,
    onSelectCollectionID,
}) => {
    const submission = useRef<{ album?: Collection }>({});
    useLayoutEffect(
        () => () => {
            submission.current = {};
        },
        [],
    );
    const handleClose = () => {
        submission.current = {};
        onClose();
    };

    const handleCreateAlbum = async (albumName: string): Promise<boolean> => {
        const pending = submission.current;
        if (!pending.album) {
            pending.album = isHidden
                ? await createHiddenAlbum(albumName)
                : await createAlbum(albumName);
        } else if (pending.album.name !== albumName) {
            await renameCollection(pending.album, albumName);
            pending.album = { ...pending.album, name: albumName };
        }
        await onRemoteFilesPull();
        if (pending !== submission.current) return false;
        onSelectCollectionID(pending.album.id);
        return true;
    };

    return (
        <SingleInputDialog
            open={open}
            onClose={handleClose}
            title={t("new_album")}
            label={t("album_name")}
            submitButtonTitle={t("create")}
            onSubmit={handleCreateAlbum}
        />
    );
};
