import { NameInputDialog } from "@/components/ui/NameInputDialog";
import type { LockerCollection } from "@/types";
import log from "ente-base/log";
import { t } from "i18next";
import { useCallback, useEffect, useState } from "react";

interface RenameCollectionDialogProps {
    collection: LockerCollection | null;
    onClose: () => void;
    onRenameCollection?: (
        collectionID: number,
        newName: string,
    ) => void | Promise<void>;
}
export function RenameCollectionDialog({
    collection,
    onClose,
    onRenameCollection,
}: RenameCollectionDialogProps) {
    const renameCollectionID = collection?.id ?? null;
    const renameCollectionOpen = collection !== null;
    const [renameValue, setRenameValue] = useState(collection?.name ?? "");
    const [renameError, setRenameError] = useState<string | null>(null);
    const [renamingCollection, setRenamingCollection] = useState(false);
    const [previousCollection, setPreviousCollection] = useState(collection);
    if (previousCollection !== collection) {
        setPreviousCollection(collection);
        if (collection) {
            setRenameValue(collection.name);
            setRenameError(null);
        }
    }
    useEffect(() => {
        if (renameCollectionID === null) {
            setRenameError(null);
            setRenamingCollection(false);
        }
    }, [renameCollectionID]);

    const handleRenameConfirm = useCallback(async () => {
        if (
            renameCollectionID === null ||
            !renameValue.trim() ||
            !onRenameCollection ||
            renamingCollection
        ) {
            return;
        }

        setRenamingCollection(true);
        setRenameError(null);
        try {
            await Promise.resolve(
                onRenameCollection(renameCollectionID, renameValue.trim()),
            );
            onClose();
            setRenameValue("");
        } catch (error) {
            log.error("Failed to rename Locker collection", error);
            setRenameError(
                error instanceof Error ? error.message : t("generic_error"),
            );
        } finally {
            setRenamingCollection(false);
        }
    }, [
        onClose,
        onRenameCollection,
        renameCollectionID,
        renameValue,
        renamingCollection,
    ]);

    const onCloseRenameDialog = () => {
        if (renamingCollection) return;
        onClose();
        setRenameError(null);
    };
    const handleNameChange = (value: string) => {
        setRenameValue(value);
        setRenameError(null);
    };
    return (
        <NameInputDialog
            open={renameCollectionOpen}
            title={t("renameCollection")}
            label={t("enterCollectionName")}
            value={renameValue}
            required
            loading={renamingCollection}
            disabled={!renameValue.trim()}
            error={renameError ?? undefined}
            onChange={handleNameChange}
            onClose={onCloseRenameDialog}
            onSubmit={() => {
                void handleRenameConfirm();
            }}
        />
    );
}
