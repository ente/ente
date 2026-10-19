import { CollectionsSortOptions } from "@/components/CollectionsSortOptions";
import { PeopleSortOptions } from "@/components/PeopleSortOptions";
import {
    matchesAlbumFilter,
    type AlbumFilter,
    type albumFilters,
} from "@/utils/album-filters";
import type { PeopleSortBy } from "@/utils/people-sort";
import {
    Delete02Icon,
    Download05Icon,
    GeometricShapes01Icon,
    Link05Icon,
    PinIcon,
    StarIcon,
    ViewOffSlashIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import AddIcon from "@mui/icons-material/Add";
import ArchiveIcon from "@mui/icons-material/Archive";
import CloseIcon from "@mui/icons-material/Close";
import ExpandMoreIcon from "@mui/icons-material/ExpandMore";
import LockOutlinedIcon from "@mui/icons-material/LockOutlined";
import PeopleIcon from "@mui/icons-material/People";
import SearchIcon from "@mui/icons-material/Search";
import {
    Box,
    ButtonBase,
    Divider,
    Drawer,
    IconButton,
    InputBase,
    Stack,
    Tooltip,
    Typography,
    styled,
    useMediaQuery,
    useTheme,
} from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { ItemCard } from "ente-new/photos/components/Tiles";
import {
    PseudoCollectionID,
    type CollectionSummaries,
    type CollectionSummary,
    type CollectionSummaryAttribute,
    type CollectionsSortBy,
} from "ente-new/photos/services/collection-summary";
import type { Person } from "ente-new/photos/services/ml/people";
import { wait } from "ente-utils/promise";
import { t } from "i18next";
import React, {
    memo,
    useEffect,
    useId,
    useMemo,
    useRef,
    useState,
} from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import {
    FixedSizeList,
    areEqual,
    type ListChildComponentProps,
} from "react-window";
import type { GalleryBarMode } from "./reducer";

export interface GalleryBarPresentationProps {
    collapsed: boolean;
    mobileDrawerProps: ModalVisibilityProps;
}

export interface GalleryBarImplProps extends GalleryBarPresentationProps {
    mode: GalleryBarMode;
    albumFilter: AlbumFilter;
    albumSearchQuery: string;
    onAlbumSearchQueryChange: (query: string) => void;
    onShowAlbumOverview: (filter: AlbumFilter) => void;
    onShowPeopleOverview: () => void;
    collectionSummaries: CollectionSummary[];
    visibleAlbumFilters: typeof albumFilters;
    normalCollectionSummaries: CollectionSummaries;
    uncategorizedCollectionSummaryID: number;
    onShowCollectionSummary: (
        collectionSummaryID: number,
        isHiddenCollectionSummary?: boolean,
    ) => Promise<boolean>;
    activeCollectionID: number | undefined;
    onSelectCollectionID: (collectionID: number) => void;
    onCreateAlbum: () => void;
    collectionsSortBy: CollectionsSortBy;
    onChangeCollectionsSortBy: (by: CollectionsSortBy) => void;
    peopleSortBy: PeopleSortBy;
    onChangePeopleSortBy: (by: PeopleSortBy) => void;
    people: Person[];
    activePerson: Person | undefined;
    onSelectPerson: (personID: string) => void;
}

export const GalleryBarImpl: React.FC<GalleryBarImplProps> = ({
    mode,
    albumFilter,
    albumSearchQuery,
    onAlbumSearchQueryChange,
    onShowAlbumOverview,
    onShowPeopleOverview,
    collectionSummaries,
    visibleAlbumFilters,
    normalCollectionSummaries,
    uncategorizedCollectionSummaryID,
    onShowCollectionSummary,
    activeCollectionID,
    onSelectCollectionID,
    onCreateAlbum,
    collectionsSortBy,
    onChangeCollectionsSortBy,
    peopleSortBy,
    onChangePeopleSortBy,
    people,
    activePerson,
    onSelectPerson,
    collapsed,
    mobileDrawerProps,
}) => {
    const mobile = useMediaQuery(useTheme().breakpoints.down("md"));
    const titleID = useId();
    const listRef = useRef<FixedSizeList | null>(null);
    const searchInputRef = useRef<HTMLInputElement>(null);
    const [peopleSearchQuery, setPeopleSearchQuery] = useState("");
    const searchQuery = mode == "people" ? peopleSearchQuery : albumSearchQuery;
    const setSearchQuery =
        mode == "people" ? setPeopleSearchQuery : onAlbumSearchQueryChange;
    const normalizedSearchQuery = searchQuery.trim().toLowerCase();
    const isSearching = !!normalizedSearchQuery;
    const matchingPeople = useMemo(
        () =>
            mode == "people" && isSearching
                ? people.filter((person) =>
                      person.name
                          ?.toLowerCase()
                          .includes(normalizedSearchQuery),
                  )
                : people,
        [mode, people, isSearching, normalizedSearchQuery],
    );
    const [viewportHeight, setViewportHeight] = useState(0);
    const [expandedAlbumFilter, setExpandedAlbumFilter] = useState<
        AlbumFilter | undefined
    >(albumFilter);
    const lastAlbumFilter = useRef(albumFilter);
    const displayedAlbumFilter =
        isSearching &&
        expandedAlbumFilter !== undefined &&
        !visibleAlbumFilters.some(({ value }) => value == expandedAlbumFilter)
            ? visibleAlbumFilters[0]?.value
            : expandedAlbumFilter;
    const displayedCollectionSummaries = useMemo(
        () =>
            mode == "albums"
                ? collectionSummaries.filter(
                      (cs) =>
                          displayedAlbumFilter !== undefined &&
                          matchesAlbumFilter(cs, displayedAlbumFilter),
                  )
                : collectionSummaries,
        [mode, collectionSummaries, displayedAlbumFilter],
    );

    useEffect(() => {
        // Heading clicks already set expansion; sync other group navigation.
        if (lastAlbumFilter.current == albumFilter) return;
        lastAlbumFilter.current = albumFilter;
        setExpandedAlbumFilter(albumFilter);
    }, [albumFilter]);
    useEffect(() => {
        setPeopleSearchQuery("");
    }, [mode]);

    useEffect(() => {
        if (
            mode == "people" &&
            (mobile ? !mobileDrawerProps.open : collapsed)
        ) {
            setPeopleSearchQuery("");
        }
    }, [mode, mobile, mobileDrawerProps.open, collapsed]);

    useEffect(() => {
        if (isSearching) listRef.current?.scrollTo(0);
    }, [searchQuery, isSearching]);

    useEffect(() => {
        if (!listRef.current || isSearching) return;
        let i = -1;
        switch (mode) {
            case "albums":
            case "hidden-albums":
            case "archive-albums":
            case "links":
                i = displayedCollectionSummaries.findIndex(
                    ({ id }) => id == activeCollectionID,
                );
                break;
            case "people":
                i = matchingPeople.findIndex(
                    ({ id }) => id == activePerson?.id,
                );
                break;
        }
        if (i != -1) listRef.current.scrollToItem(i, "smart");
    }, [
        mode,
        displayedCollectionSummaries,
        activeCollectionID,
        matchingPeople,
        activePerson,
        collapsed,
        mobile,
        mobileDrawerProps.open,
        viewportHeight,
        isSearching,
    ]);

    const itemData = useMemo<ItemData>(
        () =>
            mode == "albums" ||
            mode == "hidden-albums" ||
            mode == "archive-albums" ||
            mode == "links"
                ? {
                      type: "collections",
                      collectionSummaries: displayedCollectionSummaries,
                      indented: mode == "albums",
                      activeCollectionID: activeCollectionID!,
                      onSelectCollectionID,
                  }
                : {
                      type: "people" as const,
                      people: matchingPeople,
                      activePerson,
                      onSelectPerson,
                  },
        [
            mode,
            displayedCollectionSummaries,
            activeCollectionID,
            onSelectCollectionID,
            matchingPeople,
            activePerson,
            onSelectPerson,
        ],
    );

    const title =
        mode == "people"
            ? t("people")
            : mode == "links"
              ? t("links")
              : mode == "hidden-albums"
                ? t("hidden_albums")
                : mode == "archive-albums"
                  ? t("section_archive")
                  : t("albums");

    const albumShortcuts = [
        {
            id: uncategorizedCollectionSummaryID,
            label: t("section_uncategorized"),
            icon: GeometricShapes01Icon,
            active: activeCollectionID == uncategorizedCollectionSummaryID,
        },
        {
            id: PseudoCollectionID.hiddenItems,
            label: t("section_hidden"),
            icon: ViewOffSlashIcon,
            active: mode == "hidden-albums",
        },
        {
            id: PseudoCollectionID.archiveItems,
            label: t("section_archive"),
            icon: Download05Icon,
            active: mode == "archive-albums",
        },
        {
            id: PseudoCollectionID.trash,
            label: t("section_trash"),
            icon: Delete02Icon,
            active: activeCollectionID == PseudoCollectionID.trash,
        },
    ];

    const albumListID = `${titleID}-albums`;
    const items = (
        <Box
            id={mode == "albums" ? albumListID : undefined}
            sx={{
                flex: mode == "albums" ? "0 1 auto" : 1,
                height:
                    mode == "albums"
                        ? getItemCount(itemData) * (mobile ? 46 : 50)
                        : undefined,
                minHeight:
                    mode == "albums" && getItemCount(itemData) > 0
                        ? mobile
                            ? 46
                            : 50
                        : 0,
                minWidth: 0,
            }}
        >
            <AutoSizer onResize={({ height }) => setViewportHeight(height)}>
                {({ width, height }) => (
                    <FixedSizeList
                        ref={listRef}
                        width={width}
                        height={height}
                        itemData={itemData}
                        itemKey={getItemKey}
                        itemCount={getItemCount(itemData)}
                        itemSize={mobile ? 46 : 50}
                        style={{ overflowX: "hidden" }}
                    >
                        {ListItem}
                    </FixedSizeList>
                )}
            </AutoSizer>
        </Box>
    );

    const searchEmptyState = (
        <Stack
            role="status"
            sx={{
                flex: 1,
                minHeight: 0,
                alignItems: "center",
                justifyContent: "safe center",
                gap: "12px",
                px: "16px",
                py: "24px",
                textAlign: "center",
                overflowY: "auto",
            }}
        >
            <Box
                component="img"
                src="/images/empty-state/no-matches.svg"
                alt=""
                draggable={false}
                sx={{ width: 112, height: "auto", flexShrink: 0 }}
            />
            <Typography
                sx={{
                    color: "text.base",
                    fontFamily: '"Outfit Variable", sans-serif',
                    fontSize: 18,
                    fontWeight: 600,
                    lineHeight: "26px",
                }}
            >
                {t("no_results")}
            </Typography>
        </Stack>
    );

    const navigation = (
        <Stack
            component="nav"
            aria-labelledby={titleID}
            onKeyDown={(event) => {
                if (event.key == "Escape" && searchQuery) {
                    event.stopPropagation();
                    setSearchQuery("");
                }
            }}
            sx={(theme) => ({
                "--gallery-navigation-surface": "#FFFFFF",
                "--gallery-navigation-hover":
                    "color-mix(in srgb, var(--mui-palette-text-base) 8%, var(--gallery-navigation-surface))",
                display: collapsed && !mobile ? "none" : "flex",
                flexShrink: 0,
                width: mobile ? "100%" : 328,
                height: "100%",
                minHeight: 0,
                px: mobile ? "12px" : "16px",
                py: mobile ? "14px" : 0,
                borderLeft: mobile ? 0 : "2px solid",
                borderColor: "rgba(224, 224, 224, 0.5)",
                gap: "16px",
                letterSpacing: 0,
                ...theme.applyStyles("dark", {
                    "--gallery-navigation-surface": "#212121",
                    borderColor: "rgba(62, 62, 62, 0.5)",
                }),
            })}
        >
            <Stack
                direction="row"
                sx={{
                    alignItems: "center",
                    flexShrink: 0,
                    height: 38,
                    gap: 0.5,
                    "& .MuiIconButton-root": {
                        width: 38,
                        height: 38,
                        borderRadius: "12px",
                        bgcolor: "var(--gallery-navigation-surface)",
                        "&:hover": {
                            bgcolor: "var(--gallery-navigation-hover)",
                        },
                    },
                }}
            >
                <Typography
                    component="h2"
                    id={titleID}
                    sx={{
                        flex: 1,
                        minWidth: 0,
                        fontFamily: '"Outfit Variable", Outfit, sans-serif',
                        fontSize: mobile ? 20 : 24,
                        fontWeight: 600,
                        lineHeight: mobile ? "26px" : "32px",
                    }}
                >
                    {mode == "people" ? (
                        <ButtonBase
                            onClick={() => {
                                setPeopleSearchQuery("");
                                onShowPeopleOverview();
                                mobileDrawerProps.onClose();
                            }}
                            sx={{
                                font: "inherit",
                                justifyContent: "flex-start",
                                borderRadius: 1,
                                "&:hover": { color: "text.muted" },
                                "&.Mui-focusVisible": {
                                    outline: "2px solid",
                                    outlineColor: "primary.main",
                                    outlineOffset: 2,
                                },
                            }}
                        >
                            {title}
                        </ButtonBase>
                    ) : (
                        title
                    )}
                </Typography>
                {mode != "people" ? (
                    <CollectionsSortOptions
                        variant="v2"
                        activeSortBy={collectionsSortBy}
                        onChangeSortBy={onChangeCollectionsSortBy}
                    />
                ) : (
                    <PeopleSortOptions
                        variant="v2"
                        activeSortBy={peopleSortBy}
                        onChangeSortBy={onChangePeopleSortBy}
                    />
                )}
                {(mode == "albums" || mode == "hidden-albums") && (
                    <Tooltip title={t("new_album")}>
                        <IconButton
                            aria-label={t("new_album")}
                            aria-haspopup="dialog"
                            onClick={() => {
                                mobileDrawerProps.onClose();
                                onCreateAlbum();
                            }}
                        >
                            <AddIcon sx={{ fontSize: 20 }} />
                        </IconButton>
                    </Tooltip>
                )}
                {mobile && (
                    <IconButton
                        aria-label={t("close")}
                        onClick={mobileDrawerProps.onClose}
                    >
                        <CloseIcon sx={{ fontSize: 20 }} />
                    </IconButton>
                )}
            </Stack>
            <Stack
                direction="row"
                sx={{
                    alignItems: "center",
                    flexShrink: 0,
                    height: 52,
                    gap: "10px",
                    px: "16px",
                    borderRadius: "12px",
                    bgcolor: "var(--gallery-navigation-surface)",
                    border: "1px solid",
                    borderColor: "stroke.faint",
                    "&:focus-within": {
                        outline: "1px solid",
                        outlineColor: "stroke.muted",
                        outlineOffset: -1,
                    },
                }}
            >
                <SearchIcon sx={{ fontSize: 18, color: "text.muted" }} />
                <InputBase
                    inputRef={searchInputRef}
                    fullWidth
                    placeholder={t(
                        mode == "people"
                            ? "people_search_hint"
                            : mode == "links"
                              ? "search_links"
                              : "search_in_albums",
                    )}
                    inputProps={{
                        "aria-label": t(
                            mode == "people"
                                ? "people_search_hint"
                                : mode == "links"
                                  ? "search_links"
                                  : "search_in_albums",
                        ),
                    }}
                    value={searchQuery}
                    onChange={(event) => setSearchQuery(event.target.value)}
                    sx={{
                        fontSize: mobile ? 13 : 14,
                        fontWeight: 500,
                        color: "text.base",
                        "& input::placeholder": {
                            color: "text.muted",
                            opacity: 1,
                        },
                    }}
                />
                {searchQuery && (
                    <IconButton
                        aria-label={t("clear_search")}
                        onClick={() => {
                            setSearchQuery("");
                            searchInputRef.current?.focus();
                        }}
                        size="small"
                    >
                        <CloseIcon sx={{ fontSize: 18 }} />
                    </IconButton>
                )}
            </Stack>
            {isSearching &&
            (mode == "albums"
                ? !visibleAlbumFilters.length
                : !getItemCount(itemData)) ? (
                searchEmptyState
            ) : mode == "albums" ? (
                <Stack
                    role="group"
                    aria-label={t("filter_albums")}
                    sx={{
                        flex: 1,
                        minHeight: 0,
                        gap: "2px",
                        overflowY: "auto",
                        pb: "12px",
                    }}
                >
                    {visibleAlbumFilters.map((filter) => (
                        <React.Fragment key={filter.value}>
                            <BarCard
                                aria-label={filter.title()}
                                aria-current={
                                    activeCollectionID === undefined &&
                                    albumFilter == filter.value
                                        ? "page"
                                        : undefined
                                }
                                aria-expanded={
                                    displayedAlbumFilter == filter.value
                                }
                                aria-controls={
                                    displayedAlbumFilter == filter.value
                                        ? albumListID
                                        : undefined
                                }
                                onClick={() => {
                                    lastAlbumFilter.current = filter.value;
                                    setExpandedAlbumFilter(
                                        displayedAlbumFilter == filter.value
                                            ? undefined
                                            : filter.value,
                                    );
                                    onShowAlbumOverview(filter.value);
                                    mobileDrawerProps.onClose();
                                }}
                                sx={{ flexShrink: 0 }}
                            >
                                <CardText>{filter.label()}</CardText>
                                <ExpandMoreIcon
                                    sx={{
                                        fontSize: 16,
                                        color: "text.muted",
                                        transform:
                                            displayedAlbumFilter == filter.value
                                                ? undefined
                                                : "rotate(-90deg)",
                                    }}
                                />
                            </BarCard>
                            {displayedAlbumFilter == filter.value && items}
                        </React.Fragment>
                    ))}
                </Stack>
            ) : (
                items
            )}
            {mode != "people" && mode != "links" && (
                <Stack sx={{ flexShrink: 0, gap: "2px", pb: "8px" }}>
                    <Divider
                        sx={{
                            mb: "8px",
                            height: "2px",
                            border: 0,
                            bgcolor: "divider",
                            opacity: 0.5,
                        }}
                    />
                    {albumShortcuts.map(({ id, label, icon, active }) => (
                        <BarCard
                            key={id}
                            aria-label={label}
                            aria-current={active ? "true" : undefined}
                            onClick={() => {
                                void onShowCollectionSummary(
                                    id,
                                    id == PseudoCollectionID.hiddenItems,
                                ).then(async (success) => {
                                    if (!success || !mobile) return;
                                    if (id == PseudoCollectionID.hiddenItems)
                                        await wait(10);
                                    mobileDrawerProps.onClose();
                                });
                            }}
                            sx={{ flexShrink: 0 }}
                        >
                            <HugeiconsIcon icon={icon} size={20} aria-hidden />
                            <CardText>{label}</CardText>
                            {id == PseudoCollectionID.hiddenItems ? (
                                <LockOutlinedIcon
                                    sx={{ color: "text.muted", fontSize: 19 }}
                                />
                            ) : (
                                <Typography
                                    variant="small"
                                    sx={{ color: "text.muted" }}
                                >
                                    {
                                        normalCollectionSummaries.get(id)
                                            ?.fileCount
                                    }
                                </Typography>
                            )}
                        </BarCard>
                    ))}
                </Stack>
            )}
        </Stack>
    );

    return mobile ? (
        <Drawer
            {...mobileDrawerProps}
            anchor="left"
            slotProps={{
                backdrop: { sx: { bgcolor: "rgba(0,0,0,0.4)" } },
                paper: {
                    role: "dialog",
                    "aria-modal": true,
                    "aria-labelledby": titleID,
                    inert: !mobileDrawerProps.open,
                    sx: (theme) => ({
                        width: "100%",
                        borderRadius: 0,
                        boxShadow: "none",
                        bgcolor: "#F4F4F4",
                        ...theme.applyStyles("dark", { bgcolor: "#161616" }),
                    }),
                },
            }}
        >
            {navigation}
        </Drawer>
    ) : (
        navigation
    );
};

type ItemData =
    | {
          type: "collections";
          collectionSummaries: CollectionSummary[];
          indented: boolean;
          activeCollectionID: number;
          onSelectCollectionID: (id: number) => void;
      }
    | {
          type: "people";
          people: Person[];
          activePerson: Person | undefined;
          onSelectPerson: (personID: string) => void;
      };

const getItemCount = (data: ItemData) => {
    switch (data.type) {
        case "collections": {
            return data.collectionSummaries.length;
        }
        case "people": {
            return data.people.length;
        }
    }
};

const getItemKey = (index: number, data: ItemData) => {
    switch (data.type) {
        case "collections": {
            const collectionSummary = data.collectionSummaries[index]!;
            return `${data.type}-${collectionSummary.id}-${collectionSummary.coverFile?.id}`;
        }
        case "people": {
            const person = data.people[index]!;
            return `${data.type}-${person.id}-${person.displayFaceID}`;
        }
    }
};

const ListItem = memo((props: ListChildComponentProps<ItemData>) => {
    const { data, index, style } = props;

    let card: React.ReactNode;

    switch (data.type) {
        case "collections": {
            const {
                collectionSummaries,
                activeCollectionID,
                onSelectCollectionID,
            } = data;
            const collectionSummary = collectionSummaries[index]!;
            card = (
                <CollectionBarCard
                    key={collectionSummary.id}
                    {...{
                        collectionSummary,
                        activeCollectionID,
                        onSelectCollectionID,
                    }}
                    indented={
                        data.indented &&
                        !collectionSummary.attributes.has("system")
                    }
                />
            );
            break;
        }

        case "people": {
            const { people, activePerson, onSelectPerson } = data;
            const person = people[index]!;
            card = (
                <PersonCard
                    key={person.id}
                    {...{ person, activePerson, onSelectPerson }}
                />
            );
            break;
        }
    }

    return <div style={style}>{card}</div>;
}, areEqual);

interface CollectionBarCardProps {
    collectionSummary: CollectionSummary;
    indented: boolean;
    activeCollectionID: number;
    onSelectCollectionID: (collectionID: number) => void;
}

const CollectionBarCard: React.FC<CollectionBarCardProps> = ({
    collectionSummary,
    indented,
    activeCollectionID,
    onSelectCollectionID,
}: CollectionBarCardProps) => (
    <BarCard
        aria-label={collectionSummary.name}
        aria-current={
            activeCollectionID === collectionSummary.id ? "true" : undefined
        }
        title={collectionSummary.name}
        onClick={() => onSelectCollectionID(collectionSummary.id)}
        sx={
            indented
                ? { marginInlineStart: "20px", width: "calc(100% - 20px)" }
                : undefined
        }
    >
        <Box aria-hidden sx={{ flexShrink: 0 }}>
            <ItemCard
                TileComponent={BarThumbnail}
                coverFile={collectionSummary.coverFile}
            />
        </Box>
        <CardText>{collectionSummary.name}</CardText>
        <CollectionBarCardIcon attributes={collectionSummary.attributes} />
    </BarCard>
);

const CardText: React.FC<React.PropsWithChildren> = ({ children }) => (
    <Typography
        noWrap
        sx={(theme) => ({
            flex: 1,
            minWidth: 0,
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 14,
            fontWeight: 500,
            lineHeight: "20px",
            [theme.breakpoints.down("md")]: { fontSize: 13 },
        })}
    >
        {children}
    </Typography>
);

interface CollectionBarCardIconProps {
    attributes: Set<CollectionSummaryAttribute>;
}

const CollectionBarCardIcon: React.FC<CollectionBarCardIconProps> = ({
    attributes,
}) => (
    // A collection can show all four status icons at once.
    <CollectionBarCardIcon_ aria-hidden>
        {attributes.has("userFavorites") && (
            <HugeiconsIcon
                icon={StarIcon}
                size={16}
                fill="currentColor"
                aria-hidden
            />
        )}
        {(attributes.has("pinned") || attributes.has("shareePinned")) && (
            <HugeiconsIcon icon={PinIcon} size={14} />
        )}
        {attributes.has("shared") && !attributes.has("sharedOnlyViaLink") && (
            <PeopleIcon />
        )}
        {attributes.has("sharedViaLink") && (
            <HugeiconsIcon icon={Link05Icon} size={16} />
        )}
        {attributes.has("archived") && <ArchiveIcon sx={{ opacity: 0.48 }} />}
    </CollectionBarCardIcon_>
);

const CollectionBarCardIcon_ = styled("span")`
    display: flex;
    flex-shrink: 0;
    margin-inline-start: auto;
    align-items: center;
    gap: 4px;
    color: #969696;
    & > .MuiSvgIcon-root {
        font-size: 16px;
    }
`;

const BarCard = styled(ButtonBase)(({ theme }) => ({
    display: "flex",
    justifyContent: "flex-start",
    gap: "12px",
    width: "100%",
    height: 48,
    paddingInline: "16px 12px",
    borderRadius: "12px",
    color: theme.vars.palette.text.base,
    textAlign: "left",
    '&[aria-current="true"], &[aria-current="page"]': {
        backgroundColor: "var(--gallery-navigation-surface)",
    },
    "&:hover": { backgroundColor: "var(--gallery-navigation-hover)" },
    "&.Mui-focusVisible": {
        outline: "2px solid",
        outlineColor: theme.vars.palette.stroke.base,
        outlineOffset: -2,
    },
    [theme.breakpoints.down("md")]: { height: 44 },
}));

const BarThumbnail = styled("div")({
    width: 24,
    height: 24,
    position: "relative",
    overflow: "hidden",
    borderRadius: "6px",
    "& > img": {
        width: "100%",
        height: "100%",
        objectFit: "cover",
        display: "block",
    },
    "& .MuiSvgIcon-root": { fontSize: 18 },
});

interface PersonCardProps {
    person: Person;
    activePerson: Person | undefined;
    onSelectPerson: (personID: string) => void;
}

const PersonCard: React.FC<PersonCardProps> = ({
    person,
    activePerson,
    onSelectPerson,
}) => (
    <BarCard
        aria-label={person.name || t("unnamed_person")}
        aria-current={activePerson?.id === person.id ? "true" : undefined}
        title={person.name || t("unnamed_person")}
        onClick={() => onSelectPerson(person.id)}
    >
        <Box
            aria-hidden
            sx={{ flexShrink: 0, borderRadius: "50%", overflow: "hidden" }}
        >
            <ItemCard
                TileComponent={BarThumbnail}
                coverFile={person.displayFaceFile}
                coverFaceID={person.displayFaceID}
            />
        </Box>
        <CardText>{person.name || t("unnamed_person")}</CardText>
        {person.isPinned && (
            <CollectionBarCardIcon_ aria-hidden>
                <HugeiconsIcon icon={PinIcon} size={14} />
            </CollectionBarCardIcon_>
        )}
    </BarCard>
);
