import { lockerContentMaxWidth } from "@/styles/tokens";
import type { LockerCollection } from "@/types";
import {
    canEditCollection,
    canLeaveCollection,
    canOpenCollectionSharing,
} from "@/types";
import { Box } from "@mui/material";
import { savedLocalUser } from "ente-accounts/services/accounts-db";
import React from "react";

import { CollectionCard } from "./CollectionCard";

export const CollectionGrid: React.FC<{
    collections: LockerCollection[];
    onSelectCollection: (collectionID: number) => void;
    onShareCollection?: (collection: LockerCollection) => void;
    onLeaveCollection?: (collection: LockerCollection) => void;
    onRequestRenameCollection?: (collection: LockerCollection) => void;
    onDeleteCollection?: (collectionID: number) => void;
}> = ({
    collections,
    onSelectCollection,
    onShareCollection,
    onLeaveCollection,
    onRequestRenameCollection,
    onDeleteCollection,
}) => {
    const currentUserID = savedLocalUser()?.id;

    return (
        <Box
            sx={{
                width: "100%",
                maxWidth: lockerContentMaxWidth,
                mx: "auto",
                display: "grid",
                gap: 1,
            }}
        >
            {collections.map((collection) => (
                <CollectionCard
                    key={collection.id}
                    collection={collection}
                    onClick={() => onSelectCollection(collection.id)}
                    onShare={
                        onShareCollection &&
                        canOpenCollectionSharing(collection)
                            ? () => onShareCollection(collection)
                            : undefined
                    }
                    onLeave={
                        onLeaveCollection &&
                        canLeaveCollection(collection, currentUserID)
                            ? () => onLeaveCollection(collection)
                            : undefined
                    }
                    onRename={
                        onRequestRenameCollection &&
                        canEditCollection(collection, currentUserID)
                            ? () => onRequestRenameCollection(collection)
                            : undefined
                    }
                    onDelete={
                        onDeleteCollection &&
                        canEditCollection(collection, currentUserID)
                            ? () => onDeleteCollection(collection.id)
                            : undefined
                    }
                />
            ))}
        </Box>
    );
};
