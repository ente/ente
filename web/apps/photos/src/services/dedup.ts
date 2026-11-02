import { ensureLocalUser } from "ente-accounts/services/user";
import { assertionFailed } from "ente-base/assert";
import { newID } from "ente-base/id";
import type { EnteFile } from "ente-media/file";
import {
    FilePublicMagicMetadataData,
    metadataHash,
} from "ente-media/file-metadata";
import {
    createCollectionNameByID,
    forgetPendingFavoriteFileIDs,
    savedNormalCollections,
} from "ente-new/photos/services/collection";
import { savedCollectionFiles } from "ente-new/photos/services/photos-fdb";
import { executeDuplicateRemoval, findDuplicates } from "ente-photos-wasm";
import { ensureAuthenticatedSession } from "./authenticated-session";

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
    const collectionNameByID = createCollectionNameByID(normalCollections);
    const collectionFiles = await savedCollectionFiles();
    const { groups } = await findDuplicates({
        userId: userID,
        collections: normalCollections.map(({ id, owner }) => ({
            id,
            ownerId: owner.id,
        })),
        files: collectionFiles.map((file) => ({
            id: file.id,
            collectionId: file.collectionID,
            ownerId: file.ownerID,
            hash: metadataHash(file.metadata),
            size: file.info?.fileSize,
        })),
    });

    const duplicateGroups: DuplicateGroup[] = [];

    for (const group of groups) {
        const items = group.items
            .map(({ fileIndex, collectionIds }) => {
                const file = collectionFiles[fileIndex]!;
                const collectionName = collectionNameByID.get(
                    file.collectionID,
                );
                if (!collectionName) {
                    assertionFailed();
                    return undefined;
                }

                return {
                    file,
                    collectionIDs: new Set(collectionIds),
                    collectionName,
                };
            })
            .filter((item) => !!item);
        if (items.length < 2) continue;

        items.sort((a, b) => a.collectionName.localeCompare(b.collectionName));

        duplicateGroups.push({
            id: newID("dg_"),
            items,
            itemSize: group.itemSize,
            prunableCount: items.length - 1,
            prunableSize: group.itemSize * (items.length - 1),
            isSelected: true,
        });
    }

    return duplicateGroups;
};

export const removeSelectedDuplicateGroups = async (
    duplicateGroups: DuplicateGroup[],
    onProgress: (progress: number) => void,
    onRemoteFilesPull: () => Promise<void>,
) => {
    const selectedDuplicateGroups = duplicateGroups.filter((g) => g.isSelected);

    if (!selectedDuplicateGroups.length) {
        await onRemoteFilesPull();
        onProgress(100);
        return new Set<string>();
    }

    const filesByID = new Map(
        selectedDuplicateGroups.flatMap((group) =>
            group.items.map(({ file }) => [file.id, file] as const),
        ),
    );
    const collections = await savedNormalCollections();
    const { trashIds } = await executeDuplicateRemoval(
        await ensureAuthenticatedSession(),
        {
            groups: selectedDuplicateGroups.map((group) =>
                group.items.map(({ file, collectionIDs }) => ({
                    fileId: file.id,
                    collectionIds: [...collectionIDs],
                    caption: FilePublicMagicMetadataData.shape.caption.parse(
                        file.pubMagicMetadata?.data.caption,
                    ),
                    editedName: file.pubMagicMetadata?.data.editedName,
                    editedTime: file.pubMagicMetadata?.data.editedTime,
                })),
            ),
            collections: collections.map(({ id, key }) => ({ id, key })),
            files: [...filesByID.values()].map(({ id, collectionID, key }) => ({
                id,
                collectionId: collectionID,
                key,
            })),
        },
        (completed, total) => onProgress((completed / (total + 1)) * 100),
    );
    forgetPendingFavoriteFileIDs(trashIds);

    await onRemoteFilesPull();
    onProgress(100);

    return new Set(selectedDuplicateGroups.map((g) => g.id));
};
