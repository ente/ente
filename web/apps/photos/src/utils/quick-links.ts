import { CollectionSubType, type Collection } from "ente-media/collection";

export const visibleQuickLinks = (
    collections: Collection[],
    userID: number,
    hiddenCollectionIDs: ReadonlySet<number>,
) =>
    collections
        .filter(
            (collection) =>
                collection.owner.id == userID &&
                collection.magicMetadata?.data.subType ==
                    CollectionSubType.quicklink &&
                !collection.sharees.length &&
                collection.publicURLs.length > 0 &&
                !hiddenCollectionIDs.has(collection.id),
        )
        .sort((a, b) => b.updationTime - a.updationTime || b.id - a.id);
