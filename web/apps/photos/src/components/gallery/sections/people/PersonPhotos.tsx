import {
    Box,
    ButtonBase,
    Chip,
    Stack,
    Typography,
    styled,
} from "@mui/material";
import { ItemCard } from "ente-new/photos/components/Tiles";
import { thumbnailGridPadding } from "ente-new/photos/components/utils/thumbnail-grid-layout";
import type { Person } from "ente-new/photos/services/ml/people";
import { t } from "i18next";
import { useMemo, useState } from "react";
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
                    aria-label={t("filter_by_people")}
                    sx={{
                        alignItems: "center",
                        gap: 1,
                        overflowX: "auto",
                        scrollbarWidth: "none",
                        p: "4px",
                    }}
                >
                    <Chip
                        label={
                            <>
                                <FaceStrip
                                    people={[activePerson, ...selected].slice(
                                        0,
                                        4,
                                    )}
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
                    {rowPeople.map((person) => {
                        const name = person.name || t("unnamed_person");
                        return (
                            <FaceButton
                                key={person.id}
                                aria-label={name}
                                aria-pressed={selectedIDs.includes(person.id)}
                                title={name}
                                onClick={() => togglePerson(person.id)}
                            >
                                <FaceStrip people={[person]} />
                            </FaceButton>
                        );
                    })}
                </Stack>
            </Box>
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

const FaceStrip = ({ people }: { people: Person[] }) => (
    <Box
        component="span"
        aria-hidden
        sx={{ display: "flex", "& > :not(:first-of-type)": { ml: -1 } }}
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

const FaceButton = styled(ButtonBase)(({ theme }) => ({
    borderRadius: "50%",
    flexShrink: 0,
    padding: 2,
    border: "2px solid transparent",
    "&:hover": { borderColor: theme.vars.palette.divider },
    '&[aria-pressed="true"]': { borderColor: theme.vars.palette.primary.main },
    "&.Mui-focusVisible": {
        outline: `2px solid ${theme.vars.palette.text.primary}`,
        outlineOffset: 1,
    },
}));

const FilterPortrait = styled("span")({
    position: "relative",
    width: 32,
    height: 32,
    borderRadius: "50%",
    overflow: "hidden",
    "& > img": { width: "100%", height: "100%", objectFit: "cover" },
});
