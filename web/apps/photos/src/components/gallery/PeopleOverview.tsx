import { sortPeople, type PeopleSortBy } from "@/utils/people-sort";
import ExpandLessIcon from "@mui/icons-material/ExpandLess";
import ExpandMoreIcon from "@mui/icons-material/ExpandMore";
import {
    Box,
    Button,
    Stack,
    Typography,
    styled,
    useMediaQuery,
    useTheme,
} from "@mui/material";
import { ItemCard } from "ente-new/photos/components/Tiles";
import { UnstyledButton } from "ente-new/photos/components/UnstyledButton";
import { thumbnailGridPadding } from "ente-new/photos/components/utils/thumbnail-grid-layout";
import type { Person } from "ente-new/photos/services/ml/people";
import { t } from "i18next";
import { useMemo, useState } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import { VariableSizeList, type ListChildComponentProps } from "react-window";
import { PeopleEmptyState } from ".";

export const PeopleOverview = ({
    people,
    allPeople,
    peopleSortBy,
    onSelectPerson,
}: {
    people: Person[];
    allPeople: Person[];
    peopleSortBy: PeopleSortBy;
    onSelectPerson: (id: string) => void;
}) => {
    const mobile = useMediaQuery(useTheme().breakpoints.down("md"));
    const [showingAllPeople, setShowingAllPeople] = useState(false);
    const sortedPeople = useMemo(
        () => sortPeople(people, peopleSortBy),
        [people, peopleSortBy],
    );
    const extraPeople = useMemo(() => {
        const visiblePersonIDs = new Set(people.map(({ id }) => id));
        return sortPeople(
            allPeople.filter(
                (person) =>
                    !visiblePersonIDs.has(person.id) &&
                    !(person.type == "cgroup" && person.isHidden),
            ),
            peopleSortBy,
        );
    }, [allPeople, people, peopleSortBy]);
    const primaryPeople = people.length ? sortedPeople : extraPeople;
    const showMoreFacesButton = people.length > 0 && extraPeople.length > 0;
    const expandedPeople =
        showMoreFacesButton && showingAllPeople ? extraPeople : [];

    return (
        <Stack
            sx={{
                flex: 1,
                minHeight: 0,
                overflow: "hidden",
                px: `${thumbnailGridPadding}px`,
                gap: "24px",
            }}
        >
            <Stack
                direction="row"
                sx={{
                    alignItems: "center",
                    justifyContent: "space-between",
                    minHeight: 54,
                    flexShrink: 0,
                    gap: 2,
                }}
            >
                <Stack sx={{ gap: "2px" }}>
                    <Typography
                        component="h1"
                        sx={{
                            fontFamily: '"Outfit Variable", Outfit, sans-serif',
                            fontSize: 24,
                            fontWeight: 600,
                            lineHeight: "32px",
                        }}
                    >
                        {t("people")}
                    </Typography>
                    <Typography
                        sx={{
                            color: "text.muted",
                            fontSize: 14,
                            fontWeight: 500,
                            lineHeight: "18px",
                        }}
                    >
                        {t("people_count", { count: primaryPeople.length })}
                    </Typography>
                </Stack>
            </Stack>
            {primaryPeople.length ? (
                <Box
                    sx={{
                        flex: 1,
                        minHeight: 0,
                        "--people-tile-size": { xs: "96px", md: "140px" },
                        "--people-portrait-size": { xs: "80px", md: "120px" },
                        "--people-column-gap": { xs: "12px", md: "22px" },
                    }}
                >
                    <AutoSizer>
                        {({ width, height }) => {
                            const tileWidth = mobile ? 96 : 140;
                            const gap = mobile ? 12 : 22;
                            const columns = Math.max(
                                1,
                                Math.floor(
                                    (width - 16 + gap) / (tileWidth + gap),
                                ),
                            );
                            const primaryRowCount = Math.ceil(
                                primaryPeople.length / columns,
                            );
                            const items: PeopleListItem[] = [];
                            const addPeopleRows = (people: Person[]) => {
                                for (
                                    let index = 0;
                                    index < people.length;
                                    index += columns
                                ) {
                                    items.push({
                                        type: "people",
                                        people: people.slice(
                                            index,
                                            index + columns,
                                        ),
                                    });
                                }
                            };
                            addPeopleRows(primaryPeople);
                            if (showMoreFacesButton) {
                                items.push({ type: "showMore" });
                                if (showingAllPeople) {
                                    items.push({
                                        type: "header",
                                        count: expandedPeople.length,
                                    });
                                    addPeopleRows(expandedPeople);
                                }
                            }
                            return (
                                <VariableSizeList
                                    key={`${columns}-${mobile}-${primaryRowCount}-${showMoreFacesButton}`}
                                    width={width}
                                    height={height}
                                    style={{ scrollbarGutter: "stable" }}
                                    itemCount={items.length}
                                    estimatedItemSize={mobile ? 150 : 190}
                                    itemSize={(index) =>
                                        items[index]?.type != "people"
                                            ? 88
                                            : mobile
                                              ? 150
                                              : 190
                                    }
                                    itemKey={(index) => {
                                        const item = items[index]!;
                                        return item.type != "people"
                                            ? item.type
                                            : item.people[0]!.id;
                                    }}
                                    overscanCount={1}
                                    itemData={{
                                        items,
                                        columns,
                                        onSelectPerson,
                                        showingAllPeople,
                                        onToggleShowingAllPeople: () =>
                                            setShowingAllPeople(
                                                (value) => !value,
                                            ),
                                    }}
                                >
                                    {PeopleRow}
                                </VariableSizeList>
                            );
                        }}
                    </AutoSizer>
                </Box>
            ) : (
                <PeopleEmptyState />
            )}
        </Stack>
    );
};

type PeopleListItem =
    | { type: "people"; people: Person[] }
    | { type: "showMore" }
    | { type: "header"; count: number };

const PeopleRow = ({
    data,
    index,
    style,
}: ListChildComponentProps<{
    items: PeopleListItem[];
    columns: number;
    onSelectPerson: (id: string) => void;
    showingAllPeople: boolean;
    onToggleShowingAllPeople: () => void;
}>) => {
    const item = data.items[index]!;
    if (item.type == "header") {
        return (
            <Stack
                style={style}
                sx={{
                    justifyContent: "center",
                    borderTop: "1px solid",
                    borderColor: "stroke.faint",
                    gap: "2px",
                }}
            >
                <Typography
                    component="h2"
                    sx={{
                        fontFamily: '"Outfit Variable", Outfit, sans-serif',
                        fontSize: 20,
                        fontWeight: 600,
                        lineHeight: "26px",
                    }}
                >
                    {t("more_faces")}
                </Typography>
                <Typography
                    sx={{
                        color: "text.muted",
                        fontSize: 14,
                        lineHeight: "18px",
                    }}
                >
                    {t("people_count", { count: item.count })}
                </Typography>
            </Stack>
        );
    }
    if (item.type == "showMore") {
        return (
            <Box
                style={style}
                sx={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    py: 2,
                    gap: 2,
                }}
            >
                <Button
                    variant="text"
                    onClick={data.onToggleShowingAllPeople}
                    aria-expanded={data.showingAllPeople}
                    startIcon={
                        data.showingAllPeople ? (
                            <ExpandLessIcon />
                        ) : (
                            <ExpandMoreIcon />
                        )
                    }
                    sx={{
                        flexShrink: 0,
                        color: "text.muted",
                        bgcolor: "transparent",
                        px: 1,
                        fontSize: 14,
                        fontWeight: 500,
                        "&:hover": {
                            color: "text.base",
                            bgcolor: "transparent",
                        },
                    }}
                >
                    {data.showingAllPeople
                        ? t("show_less_faces")
                        : t("show_more_faces")}
                </Button>
            </Box>
        );
    }
    return (
        <div
            style={{
                ...style,
                display: "grid",
                gridTemplateColumns: `repeat(${data.columns}, minmax(0, 1fr))`,
                columnGap: "var(--people-column-gap)",
                justifyItems: "center",
                alignItems: "start",
            }}
        >
            {item.people.map((person) => (
                <PersonButton
                    key={person.id}
                    onClick={() => data.onSelectPerson(person.id)}
                >
                    <ItemCard
                        TileComponent={Portrait}
                        coverFile={person.displayFaceFile}
                        coverFaceID={person.displayFaceID}
                    />
                    <Typography
                        component="span"
                        sx={{
                            fontSize: 14,
                            fontWeight: 500,
                            lineHeight: "20px",
                            width: "100%",
                            overflow: "hidden",
                            textOverflow: "ellipsis",
                            whiteSpace: "nowrap",
                        }}
                    >
                        {person.name || t("unnamed_person")}
                    </Typography>
                    <Typography
                        component="span"
                        sx={{
                            mt: "-6px",
                            fontSize: 12,
                            fontWeight: 500,
                            lineHeight: "16px",
                            color: "text.muted",
                        }}
                    >
                        {t("people_photo_count", {
                            count: person.fileIDs.length,
                        })}
                    </Typography>
                </PersonButton>
            ))}
        </div>
    );
};

const PersonButton = styled(UnstyledButton)({
    width: "var(--people-tile-size)",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: 8,
    color: "inherit",
    borderRadius: 12,
    "&:hover": { opacity: 0.86 },
});

const Portrait = styled("div")({
    width: "var(--people-portrait-size)",
    height: "var(--people-portrait-size)",
    flexShrink: 0,
    borderRadius: "50%",
    overflow: "hidden",
    position: "relative",
    "& > img": { width: "100%", height: "100%", objectFit: "cover" },
});
