import {
    collectionsSortBy as supportedCollectionsSortBy,
    type CollectionsSortBy,
} from "ente-new/photos/services/collection-summary";
import { includes } from "ente-utils/type-guards";
import { useCallback, useEffect, useState } from "react";

export const useCollectionsSortBy = () => {
    const [collectionsSortBy, setCollectionsSortBy] =
        useState<CollectionsSortBy>("updation-time-desc");

    useEffect(() => {
        const value = localStorage.getItem("collectionsSortBy");
        if (value && includes(supportedCollectionsSortBy, value))
            setCollectionsSortBy(value);
    }, []);

    const onChangeCollectionsSortBy = useCallback(
        (value: CollectionsSortBy) => {
            localStorage.setItem("collectionsSortBy", value);
            setCollectionsSortBy(value);
        },
        [],
    );

    return { collectionsSortBy, onChangeCollectionsSortBy };
};
