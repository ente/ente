import { Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    Dialog,
    IconButton,
    Stack,
    Typography,
    useMediaQuery,
} from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { isSxArray } from "ente-base/components/utils/sx";
import type { Person } from "ente-new/photos/services/ml/people";
import { t } from "i18next";
import React, { useId, useState } from "react";
import {
    CollectionDialogSearchField,
    CollectionDialogTileButton,
    CollectionDialogTileCover,
} from "./CollectionDialog/Primitives";
import {
    collectionDialogFullScreenQuery,
    collectionDialogHeaderRowSx,
    collectionDialogHeaderSx,
    collectionDialogIconButtonSx,
    collectionDialogNoResultsSx,
    collectionDialogPaperSx,
    collectionDialogPeopleGridSx,
    collectionDialogTitleSx,
} from "./CollectionDialog/styles";
import { ItemCard } from "./Tiles";

export type AssignPersonDialogProps = ModalVisibilityProps & {
    people: Person[];
    title: string;
    onSelectPerson: (personID: string) => void;
};

export const AssignPersonDialog: React.FC<AssignPersonDialogProps> = ({
    open,
    onClose,
    people,
    title,
    onSelectPerson,
}) => {
    const titleID = useId();
    const isFullScreen = useMediaQuery(collectionDialogFullScreenQuery);
    const [searchTerm, setSearchTerm] = useState("");
    const query = searchTerm.trim().toLowerCase();
    const filteredPeople = query
        ? people.filter((person) => person.name?.toLowerCase().includes(query))
        : people;

    return (
        <Dialog
            {...{ open, onClose }}
            aria-labelledby={titleID}
            fullScreen={isFullScreen}
            maxWidth={false}
            slotProps={{
                paper: {
                    sx: [
                        ...(isSxArray(collectionDialogPaperSx)
                            ? collectionDialogPaperSx
                            : [collectionDialogPaperSx]),
                        {
                            boxSizing: "border-box",
                            maxHeight: isFullScreen
                                ? "100%"
                                : "min(600px, calc(100% - 64px))",
                        },
                    ],
                },
                transition: { onExited: () => setSearchTerm("") },
            }}
        >
            <Stack sx={{ ...collectionDialogHeaderSx, pb: 0, flexShrink: 0 }}>
                <Stack
                    direction="row"
                    sx={{
                        ...collectionDialogHeaderRowSx,
                        alignItems: "center",
                    }}
                >
                    <Typography
                        id={titleID}
                        component="h2"
                        sx={{
                            ...collectionDialogTitleSx,
                            fontFamily: '"Outfit Variable", Outfit, sans-serif',
                            whiteSpace: "normal",
                            overflowWrap: "anywhere",
                        }}
                    >
                        {title}
                    </Typography>
                    <IconButton
                        aria-label={t("close")}
                        onClick={onClose}
                        sx={[collectionDialogIconButtonSx, { flexShrink: 0 }]}
                    >
                        <HugeiconsIcon icon={Cancel01Icon} size={18} />
                    </IconButton>
                </Stack>
                <CollectionDialogSearchField
                    placeholder={`${t("people_search_hint")}...`}
                    value={searchTerm}
                    onChange={setSearchTerm}
                />
            </Stack>
            {filteredPeople.length ? (
                <Box sx={collectionDialogPeopleGridSx}>
                    {filteredPeople.map((person) => (
                        <CollectionDialogTileButton
                            key={person.id}
                            title={person.name}
                            onClick={() => onSelectPerson(person.id)}
                        >
                            <ItemCard
                                TileComponent={CollectionDialogTileCover}
                                coverFile={person.displayFaceFile}
                                coverFaceID={person.displayFaceID}
                            />
                            <Typography component="span" noWrap sx={nameSx}>
                                {person.name ?? ""}
                            </Typography>
                        </CollectionDialogTileButton>
                    ))}
                </Box>
            ) : (
                <Typography
                    role="status"
                    sx={{ ...collectionDialogNoResultsSx, color: "text.muted" }}
                >
                    {t("no_results")}
                </Typography>
            )}
        </Dialog>
    );
};

const nameSx = {
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
    maxWidth: "100%",
};
