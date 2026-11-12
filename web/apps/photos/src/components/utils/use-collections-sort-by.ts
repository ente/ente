import {
    collectionsSortBy as supportedCollectionsSortBy,
    type CollectionsSortBy,
} from "ente-new/photos/services/collection-summary";
import { includes } from "ente-utils/type-guards";
import { useCallback, useEffect, useState } from "react";

export const useCollectionsSortBy = (
    storageKey: string,
    initialValue: CollectionsSortBy,
) => {
    const [collectionsSortBy, setCollectionsSortBy] = useState(initialValue);

    useEffect(() => {
        const value = localStorage.getItem(storageKey);
        if (value && includes(supportedCollectionsSortBy, value))
            setCollectionsSortBy(value);
    }, [storageKey]);

    const onChangeCollectionsSortBy = useCallback(
        (value: CollectionsSortBy) => {
            localStorage.setItem(storageKey, value);
            setCollectionsSortBy(value);
        },
        [storageKey],
    );

    return { collectionsSortBy, onChangeCollectionsSortBy };
};
