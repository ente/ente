import { CollectionsSortOptions } from "@/components/CollectionsSortOptions";
import {
    matchesAlbumFilter,
    type AlbumFilter,
    type albumFilters,
} from "@/utils/album-filters";
import { ArrowDown01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import AddIcon from "@mui/icons-material/Add";
import {
    Box,
    Divider,
    IconButton,
    Stack,
    Tooltip,
    useMediaQuery,
    useTheme,
} from "@mui/material";
import {
    PseudoCollectionID,
    type CollectionSummary,
    type CollectionsSortBy,
} from "ente-new/photos/services/collection-summary";
import { wait } from "ente-utils/promise";
import { t } from "i18next";
import React, {
    memo,
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import {
    FixedSizeList,
    VariableSizeList,
    areEqual,
    type ListChildComponentProps,
} from "react-window";
import { usePhotosNavigation } from "../../navigation/PhotosNavigationContext";

import {
    BarCard,
    CardText,
    CollectionBarCard,
    NavigationEmptyState,
    NavigationFrame,
    type GalleryBarPresentationProps,
} from "../../navigation/NavigationPrimitives";
export interface AlbumsNavigationProps extends GalleryBarPresentationProps {
    mode: "albums" | "hidden-albums" | "archive-albums";
    albumExpansion: {
        value: AlbumFilter | undefined;
        onChange: (
            filter: AlbumFilter | undefined,
            selectedFilter?: AlbumFilter,
        ) => void;
    };
    albumFilter: AlbumFilter;
    albumSearchQuery: string;
    onAlbumSearchQueryChange: (query: string) => void;
    collectionSummaries: CollectionSummary[];
    visibleAlbumFilters: typeof albumFilters;
    uncategorizedCollectionSummaryID: number;
    activeCollectionID: number | undefined;
    onCreateAlbum: () => void;
    collectionsSortBy: CollectionsSortBy;
    onChangeCollectionsSortBy: (by: CollectionsSortBy) => void;
}
export const AlbumsNavigation = ({
    mode,
    albumExpansion,
    albumFilter,
    albumSearchQuery,
    onAlbumSearchQueryChange,
    collectionSummaries,
    visibleAlbumFilters,
    uncategorizedCollectionSummaryID,
    activeCollectionID,
    onCreateAlbum,
    collectionsSortBy,
    onChangeCollectionsSortBy,
    collapsed,
    mobileDrawerProps,
}: AlbumsNavigationProps) => {
    const {
        selectCollection,
        showAlbumOverview: onShowAlbumOverview,
        showCollectionSummary: onShowCollectionSummary,
    } = usePhotosNavigation();
    const { onClose: closeMobileNavigation } = mobileDrawerProps;
    const onSelectCollectionID = useCallback(
        (id: number) => {
            selectCollection(id);
            closeMobileNavigation();
        },
        [selectCollection, closeMobileNavigation],
    );
    const mobile = useMediaQuery(useTheme().breakpoints.down("md"));
    const listRef = useRef<FixedSizeList>(null);
    const albumListRef = useRef<VariableSizeList>(null);
    const [groupExpanded, setGroupExpanded] = useState(true);
    useEffect(() => {
        setGroupExpanded(true);
    }, [mode]);
    const searchQuery = albumSearchQuery;
    const normalizedSearchQuery = searchQuery.trim().toLowerCase();
    const isSearching = !!normalizedSearchQuery;
    const [viewportHeight, setViewportHeight] = useState(0);
    const { value: expandedAlbumFilter, onChange: setExpandedAlbumFilter } =
        albumExpansion;
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
        if (isSearching) {
            listRef.current?.scrollTo(0);
            albumListRef.current?.scrollTo(0);
        }
    }, [searchQuery, isSearching]);
    const itemData = useMemo(
        () => ({
            collectionSummaries: displayedCollectionSummaries,
            activeCollectionID,
            onSelectCollectionID,
            indented: mode == "hidden-albums",
        }),
        [
            displayedCollectionSummaries,
            activeCollectionID,
            onSelectCollectionID,
            mode,
        ],
    );
    const title = t(
        mode == "hidden-albums"
            ? "hidden_albums"
            : mode == "archive-albums"
              ? "section_archive"
              : "albums",
    );
    const albumShortcuts = [
        {
            id: uncategorizedCollectionSummaryID,
            label: t("section_uncategorized"),
            active: activeCollectionID == uncategorizedCollectionSummaryID,
        },
        {
            id: PseudoCollectionID.hiddenItems,
            label: t("section_hidden"),
            active: mode == "hidden-albums",
        },
        {
            id: PseudoCollectionID.archiveItems,
            label: t("section_archive"),
            active: mode == "archive-albums",
        },
        {
            id: PseudoCollectionID.trash,
            label: t("section_trash"),
            active: activeCollectionID == PseudoCollectionID.trash,
        },
    ].filter(({ label }) =>
        label.toLowerCase().includes(normalizedSearchQuery),
    );

    const items = (
        <Box sx={{ flex: 1, minHeight: 0, minWidth: 0 }}>
            <AutoSizer onResize={({ height }) => setViewportHeight(height)}>
                {({ width, height }) => (
                    <FixedSizeList
                        ref={listRef}
                        width={width}
                        height={height}
                        itemData={itemData}
                        itemKey={(i, data) =>
                            `collections-${data.collectionSummaries[i]!.id}-${data.collectionSummaries[i]!.coverFile?.id}`
                        }
                        itemCount={displayedCollectionSummaries.length}
                        itemSize={mobile ? 46 : 50}
                        style={{ overflowX: "hidden" }}
                    >
                        {ListItem}
                    </FixedSizeList>
                )}
            </AutoSizer>
        </Box>
    );

    const rowHeight = mobile ? 46 : 50;
    const albumNavigationRows: AlbumNavigationRow[] = [];
    for (const filter of visibleAlbumFilters) {
        albumNavigationRows.push({
            key: `filter-${filter.value}`,
            height: rowHeight,
            content: (
                <BarCard
                    aria-label={filter.title()}
                    aria-current={
                        activeCollectionID === undefined &&
                        albumFilter == filter.value
                            ? "page"
                            : undefined
                    }
                    aria-expanded={displayedAlbumFilter == filter.value}
                    onClick={() => {
                        setExpandedAlbumFilter(
                            displayedAlbumFilter == filter.value
                                ? undefined
                                : filter.value,
                            filter.value,
                        );
                        onShowAlbumOverview(filter.value);
                        mobileDrawerProps.onClose();
                    }}
                    sx={{ flexShrink: 0 }}
                >
                    <CardText>{filter.label()}</CardText>
                    <Box
                        component={HugeiconsIcon}
                        icon={ArrowDown01Icon}
                        size={16}
                        strokeWidth={1.8}
                        sx={{
                            color: "text.muted",
                            transform:
                                displayedAlbumFilter == filter.value
                                    ? undefined
                                    : "rotate(-90deg)",
                        }}
                    />
                </BarCard>
            ),
        });
        if (displayedAlbumFilter == filter.value) {
            for (const collectionSummary of displayedCollectionSummaries) {
                albumNavigationRows.push({
                    key: `collection-${collectionSummary.id}`,
                    height: rowHeight,
                    content: (
                        <CollectionBarCard
                            key={`${collectionSummary.id}-${collectionSummary.coverFile?.id}`}
                            collectionSummary={collectionSummary}
                            activeCollectionID={activeCollectionID}
                            onSelectCollectionID={onSelectCollectionID}
                            indented={
                                !collectionSummary.attributes.has("system")
                            }
                        />
                    ),
                });
            }
        }
    }
    if (visibleAlbumFilters.length && albumShortcuts.length) {
        albumNavigationRows.push({
            key: "shortcut-divider",
            height: 18,
            content: (
                <Divider
                    sx={{
                        mt: "8px",
                        height: "2px",
                        border: 0,
                        bgcolor: "divider",
                        opacity: 0.5,
                    }}
                />
            ),
        });
    }
    for (const { id, label, active } of albumShortcuts) {
        albumNavigationRows.push({
            key: `shortcut-${id}`,
            height: rowHeight,
            content: (
                <BarCard
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
                    <CardText>{label}</CardText>
                </BarCard>
            ),
        });
    }

    const albumRowSizes = albumNavigationRows
        .map(({ height }) => height)
        .join(",");
    const activeAlbumRowIndex = albumNavigationRows.findIndex(
        ({ key }) => key == `collection-${activeCollectionID}`,
    );
    useEffect(() => {
        albumListRef.current?.resetAfterIndex(0);
    }, [albumRowSizes]);

    useEffect(() => {
        if (isSearching) return;
        if (mode == "albums") {
            if (activeAlbumRowIndex != -1)
                albumListRef.current?.scrollToItem(
                    activeAlbumRowIndex,
                    "smart",
                );
        } else {
            const i = displayedCollectionSummaries.findIndex(
                ({ id }) => id == activeCollectionID,
            );
            if (i != -1) listRef.current?.scrollToItem(i, "smart");
        }
    }, [
        mode,
        activeAlbumRowIndex,
        displayedCollectionSummaries,
        activeCollectionID,
        collapsed,
        mobile,
        mobileDrawerProps.open,
        viewportHeight,
        isSearching,
    ]);
    const isGroupOverview =
        activeCollectionID == PseudoCollectionID.hiddenItems;
    return (
        <NavigationFrame
            title={title}
            actions={
                <>
                    <CollectionsSortOptions
                        variant="v2"
                        activeSortBy={collectionsSortBy}
                        onChangeSortBy={onChangeCollectionsSortBy}
                    />
                    {mode != "archive-albums" && (
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
                </>
            }
            searchPlaceholder={t("search_in_albums")}
            searchQuery={searchQuery}
            setSearchQuery={onAlbumSearchQueryChange}
            mobileDrawerProps={mobileDrawerProps}
        >
            {isSearching &&
            (mode == "albums"
                ? !visibleAlbumFilters.length && !albumShortcuts.length
                : !displayedCollectionSummaries.length) ? (
                <NavigationEmptyState />
            ) : mode == "albums" ? (
                <Box
                    role="group"
                    aria-label={t("filter_albums")}
                    sx={{ flex: 1, minHeight: 0, minWidth: 0 }}
                >
                    <AutoSizer
                        onResize={({ height }) => setViewportHeight(height)}
                    >
                        {({ width, height }) => (
                            <VariableSizeList
                                ref={albumListRef}
                                width={width}
                                height={height}
                                itemData={albumNavigationRows}
                                itemCount={albumNavigationRows.length}
                                itemKey={(index, rows) => rows[index]!.key}
                                itemSize={(index) =>
                                    albumNavigationRows[index]!.height
                                }
                                style={{ overflowX: "hidden" }}
                            >
                                {AlbumNavigationItem}
                            </VariableSizeList>
                        )}
                    </AutoSizer>
                </Box>
            ) : mode == "hidden-albums" ? (
                <Stack
                    role="group"
                    aria-label={t("section_hidden")}
                    sx={{ flex: 1, minHeight: 0, minWidth: 0 }}
                >
                    <BarCard
                        aria-current={isGroupOverview ? "page" : undefined}
                        aria-expanded={isSearching || groupExpanded}
                        onClick={() => {
                            setGroupExpanded(
                                !isGroupOverview || !groupExpanded,
                            );
                            onSelectCollectionID(
                                PseudoCollectionID.hiddenItems,
                            );
                            mobileDrawerProps.onClose();
                        }}
                        sx={{ flexShrink: 0, height: rowHeight }}
                    >
                        <CardText>{t("section_hidden")}</CardText>
                        <Box
                            component={HugeiconsIcon}
                            icon={ArrowDown01Icon}
                            size={16}
                            strokeWidth={1.8}
                            sx={{
                                color: "text.muted",
                                transform:
                                    isSearching || groupExpanded
                                        ? undefined
                                        : "rotate(-90deg)",
                            }}
                        />
                    </BarCard>
                    {(isSearching || groupExpanded) && items}
                </Stack>
            ) : (
                items
            )}
        </NavigationFrame>
    );
};
interface AlbumNavigationRow {
    key: string;
    height: number;
    content: React.ReactNode;
}

const AlbumNavigationItem = memo(
    ({ data, index, style }: ListChildComponentProps<AlbumNavigationRow[]>) => (
        <div style={style}>{data[index]!.content}</div>
    ),
    areEqual,
);

interface ItemData {
    collectionSummaries: CollectionSummary[];
    activeCollectionID: number | undefined;
    onSelectCollectionID: (id: number) => void;
    indented: boolean;
}
const ListItem = memo(
    ({ data, index, style }: ListChildComponentProps<ItemData>) => {
        const collectionSummary = data.collectionSummaries[index]!;
        return (
            <div style={style}>
                <CollectionBarCard
                    collectionSummary={collectionSummary}
                    activeCollectionID={data.activeCollectionID}
                    onSelectCollectionID={data.onSelectCollectionID}
                    indented={
                        data.indented &&
                        !collectionSummary.attributes.has("system")
                    }
                />
            </div>
        );
    },
    areEqual,
);
