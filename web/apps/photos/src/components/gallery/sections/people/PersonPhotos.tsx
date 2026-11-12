import {
    collectionDialogFullScreenQuery,
    collectionDialogHeaderRowSx,
    collectionDialogHeaderSx,
    collectionDialogIconButtonSx,
    collectionDialogPaperSx,
    collectionDialogTitleSx,
} from "@/components/CollectionDialog/styles";
import { Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import TuneIcon from "@mui/icons-material/Tune";
import {
    Box,
    ButtonBase,
    Chip,
    Dialog,
    DialogContent,
    IconButton,
    Stack,
    Tooltip,
    Typography,
    styled,
    useMediaQuery,
} from "@mui/material";
import { isSxArray } from "ente-base/components/utils/sx";
import { ItemCard } from "ente-new/photos/components/Tiles";
import { thumbnailGridPadding } from "ente-new/photos/components/utils/thumbnail-grid-layout";
import type { Person } from "ente-new/photos/services/ml/people";
import { t } from "i18next";
import { useId, useMemo, useState } from "react";
import { GalleryMedia } from "../../media/GalleryMedia";
import type { GallerySectionProps } from "../types";
import type { GalleryView } from "../view-types";
import { derivePeopleFilteredFiles } from "./people-files";
import { PeopleHeader } from "./PeopleHeader";

export const PersonPhotos = ({
    library,
    operations,
    navigation,
    view,
    activePerson,
}: Pick<GallerySectionProps, "library" | "operations" | "navigation"> & {
    view: Extract<GalleryView, { type: "people" }>;
    activePerson: Person;
}) => {
    const [selectedIDs, setSelectedIDs] = useState<string[]>([]);
    const [onlyThem, setOnlyThem] = useState(false);
    const [showPeopleFilter, setShowPeopleFilter] = useState(false);
    const dialogTitleID = useId();
    const isFullScreen = useMediaQuery(collectionDialogFullScreenQuery);

    const suggestions = useMemo(() => {
        const fileIDs = new Set(activePerson.fileIDs);
        return view.people
            .filter(
                (person) =>
                    person.id !== activePerson.id &&
                    !(person.type === "cgroup" && person.isHidden),
            )
            .map((person) => ({
                person,
                count: person.fileIDs.filter((id) => fileIDs.has(id)).length,
            }))
            .filter(({ count }) => count > 0)
            .sort((a, b) => b.count - a.count)
            .map(({ person }) => person);
    }, [activePerson, view.people]);

    const selected = useMemo(
        () => suggestions.filter(({ id }) => selectedIDs.includes(id)),
        [suggestions, selectedIDs],
    );
    const unassignedFaces = library.peopleState?.filesWithUnassignedFaces;
    const files = useMemo(
        () =>
            derivePeopleFilteredFiles(
                library.collectionFiles,
                library.hiddenFileIDs,
                view,
                library.user?.id,
                selected,
                onlyThem ? unassignedFaces : undefined,
            ),
        [
            library.collectionFiles,
            library.hiddenFileIDs,
            library.user?.id,
            view,
            selected,
            onlyThem,
            unassignedFaces,
        ],
    );

    const togglePerson = (id: string) =>
        setSelectedIDs((ids) =>
            ids.includes(id)
                ? ids.filter((value) => value !== id)
                : [...ids, id],
        );
    const rowPeople = [
        ...selected,
        ...suggestions
            .filter(({ id }) => !selectedIDs.includes(id))
            .slice(0, Math.max(0, 14 - selected.length)),
    ];
    const noMatches = !files.length && (onlyThem || selected.length > 0);
    return (
        <>
            <Box
                sx={{
                    flexShrink: 0,
                    minWidth: 0,
                    px: `${thumbnailGridPadding}px`,
                }}
            >
                <PeopleHeader
                    person={activePerson}
                    people={view.visiblePeople}
                />
                <Stack
                    direction="row"
                    role="group"
                    aria-label={t("people")}
                    sx={{ alignItems: "center", gap: 1 }}
                >
                    {suggestions.length > 0 && (
                        <Tooltip title={t("add_more_people")}>
                            <IconButton
                                aria-label={t("add_more_people")}
                                aria-haspopup="dialog"
                                onClick={() => setShowPeopleFilter(true)}
                                sx={{ flexShrink: 0 }}
                            >
                                <TuneIcon fontSize="small" />
                            </IconButton>
                        </Tooltip>
                    )}
                    <Stack
                        direction="row"
                        sx={{
                            alignItems: "center",
                            gap: 1,
                            minWidth: 0,
                            overflowX: "auto",
                            scrollbarWidth: "none",
                            p: "4px",
                        }}
                    >
                        <Chip
                            label={
                                <>
                                    <FaceStrip
                                        people={[
                                            activePerson,
                                            ...selected,
                                        ].slice(0, 4)}
                                    />
                                    {t("only_them")}
                                </>
                            }
                            aria-pressed={onlyThem}
                            onClick={() => setOnlyThem((value) => !value)}
                            color={onlyThem ? "primary" : "default"}
                            sx={{
                                flexShrink: 0,
                                height: 38,
                                "& .MuiChip-label": {
                                    display: "flex",
                                    alignItems: "center",
                                    gap: 0.75,
                                    pl: "4px",
                                },
                            }}
                        />
                        {rowPeople.map((person) => (
                            <PersonFilterButton
                                key={person.id}
                                person={person}
                                selected={selectedIDs.includes(person.id)}
                                onClick={() => togglePerson(person.id)}
                            />
                        ))}
                    </Stack>
                </Stack>
            </Box>
            <Dialog
                open={showPeopleFilter}
                onClose={() => setShowPeopleFilter(false)}
                aria-labelledby={dialogTitleID}
                maxWidth={false}
                fullScreen={isFullScreen}
                slotProps={{
                    paper: {
                        sx: [
                            ...(isSxArray(collectionDialogPaperSx)
                                ? collectionDialogPaperSx
                                : [collectionDialogPaperSx]),
                            {
                                boxSizing: "border-box",
                                "&.MuiDialog-paper": {
                                    height: isFullScreen ? "100%" : "480px",
                                },
                            },
                        ],
                    },
                }}
            >
                <Stack
                    direction="row"
                    sx={{
                        ...collectionDialogHeaderSx,
                        ...collectionDialogHeaderRowSx,
                        alignItems: "center",
                        flexShrink: 0,
                    }}
                >
                    <Typography
                        id={dialogTitleID}
                        component="h2"
                        sx={{
                            ...collectionDialogTitleSx,
                            fontFamily: '"Outfit Variable", Outfit, sans-serif',
                            whiteSpace: "normal",
                            overflowWrap: "anywhere",
                        }}
                    >
                        {t("add_more_people")}
                    </Typography>
                    <IconButton
                        aria-label={t("close")}
                        onClick={() => setShowPeopleFilter(false)}
                        sx={[collectionDialogIconButtonSx, { flexShrink: 0 }]}
                    >
                        <HugeiconsIcon icon={Cancel01Icon} size={18} />
                    </IconButton>
                </Stack>
                <DialogContent
                    sx={{
                        minHeight: 0,
                        overflowY: "auto",
                        scrollbarGutter: "stable",
                        scrollbarWidth: "thin",
                        "&&&": { px: "20px", pb: "20px" },
                    }}
                >
                    <Box
                        sx={{
                            display: "grid",
                            gridTemplateColumns:
                                "repeat(auto-fill, minmax(78px, 1fr))",
                            gap: "12px 8px",
                        }}
                    >
                        {suggestions.map((person) => (
                            <PersonFilterButton
                                key={person.id}
                                person={person}
                                selected={selectedIDs.includes(person.id)}
                                onClick={() => {
                                    togglePerson(person.id);
                                    setShowPeopleFilter(false);
                                }}
                                showName
                            />
                        ))}
                    </Box>
                </DialogContent>
            </Dialog>
            {noMatches ? (
                <Typography
                    role="status"
                    sx={{ textAlign: "center", color: "text.muted", py: 1.5 }}
                >
                    {t("no_results")}
                </Typography>
            ) : (
                <GalleryMedia
                    {...{ library, operations, navigation }}
                    source={{
                        mode: "people",
                        modePlus: "people",
                        files,
                        activeCollectionID: undefined,
                        activePersonID: activePerson.id,
                        activeCollectionSummary: undefined,
                        disableGrouping: false,
                    }}
                />
            )}
        </>
    );
};

const PersonFilterButton = ({
    person,
    selected,
    onClick,
    showName = false,
}: {
    person: Person;
    selected: boolean;
    onClick: () => void;
    showName?: boolean;
}) => {
    const name = person.name || t("unnamed_person");
    return (
        <FaceButton
            showName={showName}
            aria-label={name}
            aria-pressed={selected}
            title={name}
            onClick={onClick}
        >
            <FaceStrip people={[person]} size={showName ? 52 : 32} />
            {showName && (
                <Typography
                    component="span"
                    noWrap
                    sx={{
                        maxWidth: "100%",
                        color: "text.muted",
                        opacity: 0.7,
                        fontSize: 12,
                        fontWeight: 500,
                        lineHeight: "16px",
                        textAlign: "center",
                    }}
                >
                    {name.trim().split(/\s+/, 1)[0]}
                </Typography>
            )}
        </FaceButton>
    );
};

const FaceStrip = ({
    people,
    size = 32,
}: {
    people: Person[];
    size?: number;
}) => (
    <Box
        component="span"
        aria-hidden
        sx={{
            display: "flex",
            "& > span": { width: size, height: size },
            "& > :not(:first-of-type)": { ml: -1 },
        }}
    >
        {people.map((person) => (
            <ItemCard
                key={person.id}
                TileComponent={FilterPortrait}
                coverFile={person.displayFaceFile}
                coverFaceID={person.displayFaceID}
            />
        ))}
    </Box>
);

const FaceButton = styled(ButtonBase, {
    shouldForwardProp: (prop) => prop !== "showName",
})<{ showName: boolean }>(({ theme, showName }) => ({
    borderRadius: showName ? 12 : "50%",
    flexShrink: 0,
    ...(showName && {
        flexDirection: "column",
        justifyContent: "start",
        gap: 4,
    }),
    "& > span:first-of-type": {
        padding: 2,
        border: "2px solid transparent",
        borderRadius: "50%",
    },
    "&:hover > span:first-of-type": { borderColor: theme.vars.palette.divider },
    '&[aria-pressed="true"] > span:first-of-type': {
        borderColor: theme.vars.palette.primary.main,
    },
    "&.Mui-focusVisible": {
        outline: `2px solid ${theme.vars.palette.text.primary}`,
        outlineOffset: 1,
    },
}));

const FilterPortrait = styled("span")({
    position: "relative",
    borderRadius: "50%",
    overflow: "hidden",
    "& > img": { width: "100%", height: "100%", objectFit: "cover" },
});
