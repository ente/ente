import { CollectionsSortOptions } from "@/components/CollectionsSortOptions";
import { ArrowDown01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Stack, useMediaQuery, useTheme } from "@mui/material";
import type {
    CollectionSummary,
    CollectionsSortBy,
} from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import { memo, useEffect, useMemo, useRef, useState } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import {
    FixedSizeList,
    areEqual,
    type ListChildComponentProps,
} from "react-window";
import {
    BarCard,
    CardText,
    CollectionBarCard,
    NavigationEmptyState,
    NavigationFrame,
    type GalleryBarPresentationProps,
} from "../../navigation/NavigationPrimitives";
import { usePhotosNavigation } from "../../navigation/PhotosNavigationContext";

interface LinksNavigationProps extends GalleryBarPresentationProps {
    collectionSummaries: CollectionSummary[];
    selectedLinkID: number | undefined;
    searchQuery: string;
    onSearchQueryChange: (query: string) => void;
    collectionsSortBy: CollectionsSortBy;
    onChangeCollectionsSortBy: (by: CollectionsSortBy) => void;
}

export const LinksNavigation = ({
    collectionSummaries,
    selectedLinkID,
    searchQuery,
    onSearchQueryChange,
    collectionsSortBy,
    onChangeCollectionsSortBy,
    collapsed,
    mobileDrawerProps,
}: LinksNavigationProps) => {
    const {
        selectCollection: onSelectLink,
        showLinksOverview: onShowOverview,
    } = usePhotosNavigation();
    const { onClose } = mobileDrawerProps;
    const mobile = useMediaQuery(useTheme().breakpoints.down("md"));
    const listRef = useRef<FixedSizeList>(null);
    const [groupExpanded, setGroupExpanded] = useState(true);
    const [viewportHeight, setViewportHeight] = useState(0);
    const isSearching = !!searchQuery.trim().toLowerCase();
    const isGroupOverview = selectedLinkID === undefined;
    const rowHeight = mobile ? 46 : 50;
    const itemData = useMemo(
        () => ({
            collectionSummaries,
            activeCollectionID: selectedLinkID,
            onSelectCollectionID: (id: number) => {
                onSelectLink(id);
                onClose();
            },
        }),
        [collectionSummaries, selectedLinkID, onSelectLink, onClose],
    );

    useEffect(() => {
        if (isSearching) listRef.current?.scrollTo(0);
    }, [searchQuery, isSearching]);
    useEffect(() => {
        if (isSearching || !listRef.current) return;
        const i = collectionSummaries.findIndex(
            ({ id }) => id === selectedLinkID,
        );
        if (i !== -1) listRef.current.scrollToItem(i, "smart");
    }, [
        collectionSummaries,
        selectedLinkID,
        collapsed,
        mobile,
        mobileDrawerProps.open,
        viewportHeight,
        isSearching,
    ]);

    return (
        <NavigationFrame
            title={t("links")}
            actions={
                <CollectionsSortOptions
                    variant="v2"
                    activeSortBy={collectionsSortBy}
                    onChangeSortBy={onChangeCollectionsSortBy}
                />
            }
            searchPlaceholder={t("search_links")}
            searchQuery={searchQuery}
            setSearchQuery={onSearchQueryChange}
            mobileDrawerProps={mobileDrawerProps}
        >
            {isSearching && !collectionSummaries.length ? (
                <NavigationEmptyState />
            ) : (
                <Stack
                    role="group"
                    aria-label={t("links")}
                    sx={{ flex: 1, minHeight: 0, minWidth: 0 }}
                >
                    <BarCard
                        aria-current={isGroupOverview ? "page" : undefined}
                        aria-expanded={isSearching || groupExpanded}
                        onClick={() => {
                            setGroupExpanded(
                                !isGroupOverview || !groupExpanded,
                            );
                            onShowOverview();
                            onClose();
                        }}
                        sx={{ flexShrink: 0, height: rowHeight }}
                    >
                        <CardText>{t("links")}</CardText>
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
                    {(isSearching || groupExpanded) && (
                        <Box sx={{ flex: 1, minHeight: 0, minWidth: 0 }}>
                            <AutoSizer
                                onResize={({ height }) =>
                                    setViewportHeight(height)
                                }
                            >
                                {({ width, height }) => (
                                    <FixedSizeList
                                        ref={listRef}
                                        width={width}
                                        height={height}
                                        itemData={itemData}
                                        itemKey={(index, data) =>
                                            `collections-${data.collectionSummaries[index]!.id}-${data.collectionSummaries[index]!.coverFile?.id}`
                                        }
                                        itemCount={collectionSummaries.length}
                                        itemSize={rowHeight}
                                        style={{ overflowX: "hidden" }}
                                    >
                                        {LinkRow}
                                    </FixedSizeList>
                                )}
                            </AutoSizer>
                        </Box>
                    )}
                </Stack>
            )}
        </NavigationFrame>
    );
};

const LinkRow = memo(
    ({
        data,
        index,
        style,
    }: ListChildComponentProps<{
        collectionSummaries: CollectionSummary[];
        activeCollectionID: number | undefined;
        onSelectCollectionID: (id: number) => void;
    }>) => {
        const collectionSummary = data.collectionSummaries[index]!;
        return (
            <div style={style}>
                <CollectionBarCard
                    key={collectionSummary.id}
                    collectionSummary={collectionSummary}
                    activeCollectionID={data.activeCollectionID}
                    onSelectCollectionID={data.onSelectCollectionID}
                    indented={!collectionSummary.attributes.has("system")}
                />
            </div>
        );
    },
    areEqual,
);
