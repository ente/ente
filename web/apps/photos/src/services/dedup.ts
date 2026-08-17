import { ensureLocalUser } from "ente-accounts/services/user";
import { assertionFailed } from "ente-base/assert";
import { newID } from "ente-base/id";
import type { EnteFile } from "ente-media/file";
import { metadataHash } from "ente-media/file-metadata";
import {
    addToCollection,
    createCollectionNameByID,
    moveToTrash,
    savedNormalCollections,
} from "ente-new/photos/services/collection";
import { savedCollectionFiles } from "ente-new/photos/services/photos-fdb";
import { pullFiles } from "./pull";

export interface DuplicateGroup {
    id: string;
    items: {
        file: EnteFile;
        collectionIDs: Set<number>;
        collectionName: string;
    }[];
    itemSize: number;
    prunableCount: number;
    prunableSize: number;
    isSelected: boolean;
}

export const deduceDuplicates = async () => {
    const userID = ensureLocalUser().id;

    const normalCollections = await savedNormalCollections();
    const normalOwnedCollections = normalCollections.filter(
        ({ owner }) => owner.id == userID,
    );
    const allowedCollectionIDs = new Set(
        normalOwnedCollections.map(({ id }) => id),
    );
    const collectionNameByID = createCollectionNameByID(normalOwnedCollections);

    const collectionFiles = await savedCollectionFiles();
    const filteredCollectionFiles = collectionFiles.filter((f) =>
        allowedCollectionIDs.has(f.collectionID),
    );

    // One file ID can appear once per collection; hash it only once.
    const collectionIDsByFileID = new Map<number, Set<number>>();
    const filesByHash = new Map<string, EnteFile[]>();
    for (const file of filteredCollectionFiles) {
        // An owned album can contain files the user does not own.
        if (file.ownerID != userID) continue;

        const hash = metadataHash(file.metadata);
        if (!hash) {
            continue;
        }

        let collectionIDs = collectionIDsByFileID.get(file.id);
        if (!collectionIDs) {
            collectionIDsByFileID.set(file.id, (collectionIDs = new Set()));
            filesByHash.set(hash, [...(filesByHash.get(hash) ?? []), file]);
        }
        collectionIDs.add(file.collectionID);
    }

    const duplicateGroups: DuplicateGroup[] = [];

    for (const duplicates of filesByHash.values()) {
        if (duplicates.length < 2) continue;

        // Live-photo ZIP sizes can vary by client despite matching content hashes.
        let size = 0;
        for (const file of duplicates) {
            if (file.info?.fileSize) {
                size = file.info.fileSize;
                break;
            }
        }

        if (!size) continue;

        const items = duplicates
            .map((file) => {
                const collectionName = collectionNameByID.get(
                    file.collectionID,
                );
                const collectionIDs = collectionIDsByFileID.get(file.id);
                if (!collectionName || !collectionIDs) {
                    assertionFailed();
                    return undefined;
                }

                return { file, collectionIDs, collectionName };
            })
            .filter((item) => !!item);
        if (items.length < 2) continue;

        items.sort((a, b) => a.collectionName.localeCompare(b.collectionName));

        duplicateGroups.push({
            id: newID("dg_"),
            items,
            itemSize: size,
            prunableCount: items.length - 1,
            prunableSize: size * (items.length - 1),
            isSelected: true,
        });
    }

    return duplicateGroups;
};

export const removeSelectedDuplicateGroups = async (
    duplicateGroups: DuplicateGroup[],
    onProgress: (progress: number) => void,
) => {
    const selectedDuplicateGroups = duplicateGroups.filter((g) => g.isSelected);

    // Symlink the retained file into every affected album before trashing duplicates.
    const filesToAdd = new Map<number, EnteFile[]>();
    const filesToTrash: EnteFile[] = [];

    for (const duplicateGroup of selectedDuplicateGroups) {
        const retainedItem = duplicateGroupItemToRetain(duplicateGroup);

        let collectionIDs = new Set<number>();
        for (const item of duplicateGroup.items) {
            if (item.file.id == retainedItem.file.id) continue;
            collectionIDs = collectionIDs.union(item.collectionIDs);
            filesToTrash.push(item.file);
        }

        collectionIDs = collectionIDs.difference(retainedItem.collectionIDs);

        for (const collectionID of collectionIDs) {
            filesToAdd.set(collectionID, [
                ...(filesToAdd.get(collectionID) ?? []),
                retainedItem.file,
            ]);
        }
    }

    let np = 0;
    const ntotal =
        filesToAdd.size + (filesToTrash.length ? 1 : 0) + /* sync */ 1;
    const tickProgress = () => onProgress((++np / ntotal) * 100);

    const collections = await savedNormalCollections();
    const collectionsByID = new Map(collections.map((c) => [c.id, c]));
    for (const [collectionID, files] of filesToAdd.entries()) {
        await addToCollection(collectionsByID.get(collectionID)!, files);
        tickProgress();
    }

    if (filesToTrash.length) {
        await moveToTrash(filesToTrash);
        tickProgress();
    }

    await pullFiles();
    tickProgress();

    return new Set(selectedDuplicateGroups.map((g) => g.id));
};

const duplicateGroupItemToRetain = (duplicateGroup: DuplicateGroup) => {
    const itemsWithCaption: DuplicateGroup["items"] = [];
    const itemsWithOtherEdits: DuplicateGroup["items"] = [];
    for (const item of duplicateGroup.items) {
        const pubMM = item.file.pubMagicMetadata?.data;
        if (!pubMM) continue;
        if (pubMM.caption) itemsWithCaption.push(item);
        if (pubMM.editedName ?? pubMM.editedTime)
            itemsWithOtherEdits.push(item);
    }

    return (
        itemsWithCaption[0] ??
        itemsWithOtherEdits[0] ??
        duplicateGroup.items[0]!
    );
};
