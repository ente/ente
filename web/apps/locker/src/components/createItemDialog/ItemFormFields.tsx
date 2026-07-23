import { CollectionChipRow } from "@/components/createItemDialog/CollectionChipRow";
import type { LockerCollection, LockerItemType } from "@/types";
import CheckRoundedIcon from "@mui/icons-material/CheckRounded";
import VisibilityIcon from "@mui/icons-material/Visibility";
import VisibilityOffIcon from "@mui/icons-material/VisibilityOff";
import {
    Box,
    IconButton,
    InputAdornment,
    Stack,
    TextField,
    Typography,
} from "@mui/material";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { t } from "i18next";
import React, { useCallback, useMemo, useState } from "react";

export const ItemFormFields: React.FC<{
    type: LockerItemType;
    data: Record<string, string>;
    onChange: (field: string, value: string) => void;
    showPassword: boolean;
    onTogglePassword: () => void;
}> = ({ type, data, onChange, showPassword, onTogglePassword }) => {
    switch (type) {
        case "note":
            return (
                <Stack sx={{ gap: 2 }}>
                    <TextField
                        label={t("noteName")}
                        value={data.title ?? ""}
                        onChange={(event) =>
                            onChange("title", event.target.value)
                        }
                        fullWidth
                        required
                        autoFocus
                    />
                    <TextField
                        label={t("noteContent")}
                        value={data.content ?? ""}
                        onChange={(event) =>
                            onChange("content", event.target.value)
                        }
                        fullWidth
                        required
                        multiline
                        minRows={4}
                        maxRows={10}
                    />
                </Stack>
            );
        case "accountCredential":
            return (
                <Stack sx={{ gap: 2 }}>
                    <TextField
                        label={t("credentialName")}
                        value={data.name ?? ""}
                        onChange={(event) =>
                            onChange("name", event.target.value)
                        }
                        fullWidth
                        required
                        autoFocus
                    />
                    <TextField
                        label={t("username")}
                        value={data.username ?? ""}
                        onChange={(event) =>
                            onChange("username", event.target.value)
                        }
                        fullWidth
                        required
                    />
                    <TextField
                        label={t("password")}
                        value={data.password ?? ""}
                        onChange={(event) =>
                            onChange("password", event.target.value)
                        }
                        fullWidth
                        required
                        type={showPassword ? "text" : "password"}
                        slotProps={{
                            input: {
                                endAdornment: (
                                    <InputAdornment position="end">
                                        <IconButton
                                            onClick={onTogglePassword}
                                            edge="end"
                                            size="small"
                                        >
                                            {showPassword ? (
                                                <VisibilityOffIcon />
                                            ) : (
                                                <VisibilityIcon />
                                            )}
                                        </IconButton>
                                    </InputAdornment>
                                ),
                            },
                        }}
                    />
                    <TextField
                        label={t("credentialNotes")}
                        value={data.notes ?? ""}
                        onChange={(event) =>
                            onChange("notes", event.target.value)
                        }
                        fullWidth
                        multiline
                        minRows={2}
                        maxRows={5}
                    />
                </Stack>
            );
        case "physicalRecord":
            return (
                <Stack sx={{ gap: 2 }}>
                    <TextField
                        label={t("recordName")}
                        value={data.name ?? ""}
                        onChange={(event) =>
                            onChange("name", event.target.value)
                        }
                        fullWidth
                        required
                        autoFocus
                    />
                    <TextField
                        label={t("recordLocation")}
                        value={data.location ?? ""}
                        onChange={(event) =>
                            onChange("location", event.target.value)
                        }
                        fullWidth
                        required
                    />
                    <TextField
                        label={t("recordNotes")}
                        value={data.notes ?? ""}
                        onChange={(event) =>
                            onChange("notes", event.target.value)
                        }
                        fullWidth
                        multiline
                        minRows={2}
                        maxRows={5}
                    />
                </Stack>
            );
        case "emergencyContact":
            return (
                <Stack sx={{ gap: 2 }}>
                    <TextField
                        label={t("contactName")}
                        value={data.name ?? ""}
                        onChange={(event) =>
                            onChange("name", event.target.value)
                        }
                        fullWidth
                        required
                        autoFocus
                    />
                    <TextField
                        label={t("contactDetails")}
                        value={data.contactDetails ?? ""}
                        onChange={(event) =>
                            onChange("contactDetails", event.target.value)
                        }
                        fullWidth
                        required
                    />
                    <TextField
                        label={t("contactNotes")}
                        value={data.notes ?? ""}
                        onChange={(event) =>
                            onChange("notes", event.target.value)
                        }
                        fullWidth
                        multiline
                        minRows={2}
                        maxRows={5}
                    />
                </Stack>
            );
        case "file":
            return (
                <Stack sx={{ gap: 2 }}>
                    <TextField
                        label={t("fileTitle")}
                        value={data.name ?? ""}
                        onChange={(event) =>
                            onChange("name", event.target.value)
                        }
                        fullWidth
                        required
                        autoFocus
                    />
                </Stack>
            );
        default:
            return null;
    }
};

export const CollectionSelector: React.FC<{
    collections: LockerCollection[];
    selectedIDs: number[];
    initialSelectedIDs?: number[];
    onToggle: (id: number) => void;
    onCreateCollection?: (name: string) => Promise<number>;
}> = ({
    collections,
    selectedIDs,
    initialSelectedIDs,
    onToggle,
    onCreateCollection,
}) => {
    const [createOpen, setCreateOpen] = useState(false);
    const [createName, setCreateName] = useState("");
    const [creating, setCreating] = useState(false);
    const [createError, setCreateError] = useState<string | null>(null);
    const [newlyCreatedCollectionIDs, setNewlyCreatedCollectionIDs] = useState<
        number[]
    >([]);

    const orderedCollections = useMemo(() => {
        const sortedCollections = [...collections].sort((a, b) =>
            a.name.localeCompare(b.name, undefined, { sensitivity: "base" }),
        );
        const pinnedCollectionIDs = [
            ...newlyCreatedCollectionIDs,
            ...(initialSelectedIDs ?? []).filter(
                (id) => !newlyCreatedCollectionIDs.includes(id),
            ),
        ];
        if (pinnedCollectionIDs.length === 0) {
            return sortedCollections;
        }

        const sortedCollectionsByID = new Map(
            sortedCollections.map((collection) => [collection.id, collection]),
        );
        const pinnedCollectionIDSet = new Set(pinnedCollectionIDs);
        const pinnedCollections = pinnedCollectionIDs
            .map((id) => sortedCollectionsByID.get(id))
            .filter(
                (collection): collection is LockerCollection => !!collection,
            );
        const remainingCollections = sortedCollections.filter(
            (collection) => !pinnedCollectionIDSet.has(collection.id),
        );
        return [...pinnedCollections, ...remainingCollections];
    }, [collections, initialSelectedIDs, newlyCreatedCollectionIDs]);

    const handleCreateCollection = useCallback(async () => {
        const name = createName.trim();
        if (!onCreateCollection || !name) {
            return;
        }

        setCreating(true);
        setCreateError(null);
        try {
            const newCollectionID = await onCreateCollection(name);
            setNewlyCreatedCollectionIDs((current) => [
                newCollectionID,
                ...current.filter((id) => id !== newCollectionID),
            ]);
            onToggle(newCollectionID);
            setCreateName("");
            setCreateOpen(false);
        } catch (error) {
            setCreateError(
                error instanceof Error
                    ? error.message
                    : t("failedToCreateCollection"),
            );
        } finally {
            setCreating(false);
        }
    }, [createName, onCreateCollection, onToggle]);

    return (
        <Box>
            <CollectionChipRow
                items={orderedCollections.map((collection) => ({
                    key: String(collection.id),
                    label: collection.name,
                    selected: selectedIDs.includes(collection.id),
                    onClick: () => onToggle(collection.id),
                }))}
                createOpen={createOpen}
                onCreateClick={
                    onCreateCollection
                        ? () => {
                              setCreateOpen((open) => !open);
                              setCreateError(null);
                          }
                        : undefined
                }
            />

            {createOpen && onCreateCollection && (
                <Stack sx={{ gap: 1, mt: 1.5 }}>
                    <Stack
                        direction="row"
                        sx={{ gap: 1, alignItems: "center" }}
                    >
                        <TextField
                            size="small"
                            fullWidth
                            autoFocus
                            placeholder={t("enterCollectionName")}
                            sx={{
                                "& .MuiInputBase-root": {
                                    height: 48,
                                    borderRadius: "14px",
                                },
                                "& .MuiInputBase-input": { pt: 1, pb: 0.5 },
                            }}
                            value={createName}
                            onChange={(event) => {
                                setCreateName(event.target.value);
                                setCreateError(null);
                            }}
                            onKeyDown={(event) => {
                                if (event.key === "Escape") {
                                    event.preventDefault();
                                    event.stopPropagation();
                                    setCreateOpen(false);
                                    setCreateError(null);
                                    return;
                                }
                                if (event.key === "Enter") {
                                    event.preventDefault();
                                    void handleCreateCollection();
                                }
                            }}
                        />
                        <LoadingButton
                            color="accent"
                            loading={creating}
                            disabled={!createName.trim()}
                            aria-label={t("create")}
                            onClick={() => void handleCreateCollection()}
                            sx={{
                                minWidth: 0,
                                width: 48,
                                height: 48,
                                p: 0,
                                borderRadius: "14px",
                                flexShrink: 0,
                            }}
                        >
                            <CheckRoundedIcon />
                        </LoadingButton>
                    </Stack>
                    {createError && (
                        <Typography
                            variant="small"
                            sx={{ color: "critical.main" }}
                        >
                            {createError}
                        </Typography>
                    )}
                </Stack>
            )}
        </Box>
    );
};
