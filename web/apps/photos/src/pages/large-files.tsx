import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import ImageIcon from "@mui/icons-material/Image";
import VideocamIcon from "@mui/icons-material/Videocam";
import {
    Box,
    Chip,
    IconButton,
    LinearProgress,
    Stack,
    styled,
    Typography,
} from "@mui/material";
import { useRedirectIfNeedsCredentials } from "ente-accounts/components/utils/use-redirect";
import { CenteredFill, Overlay } from "ente-base/components/containers";
import { ActivityErrorIndicator } from "ente-base/components/ErrorIndicator";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { FileViewer } from "ente-gallery/components/viewer/FileViewer";
import { formattedByteSize } from "ente-gallery/utils/units";
import {
    ItemCard,
    LargeFileTileOverlay,
} from "ente-new/photos/components/Tiles";
import {
    computeThumbnailGridLayoutParams,
    type ThumbnailGridLayoutParams,
} from "ente-new/photos/components/utils/thumbnail-grid-layout";
import {
    deleteSelectedLargeFiles,
    findLargeFiles,
    largeFilesInitialState,
    largeFilesReducer,
    type LargeFileFilter,
    type LargeFileItem,
} from "ente-new/photos/services/large-files";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, {
    memo,
    useCallback,
    useEffect,
    useMemo,
    useReducer,
    useState,
} from "react";
import Autosizer from "react-virtualized-auto-sizer";
import {
    areEqual,
    VariableSizeList,
    type ListChildComponentProps,
} from "react-window";

const Page: React.FC = () => {
    const { showMiniDialog, onGenericError } = useBaseContext();

    const [state, dispatch] = useReducer(
        largeFilesReducer,
        largeFilesInitialState,
    );
    const [openFileViewer, setOpenFileViewer] = useState(false);
    const [currentIndex, setCurrentIndex] = useState(0);

    useRedirectIfNeedsCredentials("/large-files");

    useEffect(() => {
        // Track if this effect is still current to prevent race conditions
        let isCurrent = true;

        dispatch({ type: "analyze" });
        void findLargeFiles(state.filter)
            .then((largeFiles) => {
                if (isCurrent) {
                    dispatch({ type: "analysisCompleted", largeFiles });
                }
            })
            .catch((e: unknown) => {
                if (isCurrent) {
                    log.error("Failed to find large files", e);
                    dispatch({ type: "analysisFailed" });
                }
            });

        return () => {
            isCurrent = false;
        };
    }, [state.filter]);

    const handleDeleteFiles = useCallback(() => {
        showMiniDialog({
            title: t("trash_files_title"),
            message: t("trash_files_message"),
            continue: {
                text: t("move_to_trash"),
                color: "critical",
                action: () => {
                    dispatch({ type: "delete" });
                    void deleteSelectedLargeFiles(
                        state.largeFiles,
                        (progress: number) =>
                            dispatch({ type: "setDeleteProgress", progress }),
                    )
                        .then((removedIDs) =>
                            dispatch({ type: "deleteCompleted", removedIDs }),
                        )
                        .catch((e: unknown) => {
                            onGenericError(e);
                            dispatch({ type: "deleteFailed" });
                        });
                },
            },
        });
    }, [showMiniDialog, onGenericError, state.largeFiles]);

    const handleOpenViewer = useCallback((index: number) => {
        setCurrentIndex(index);
        setOpenFileViewer(true);
    }, []);

    const handleCloseViewer = useCallback(() => {
        setOpenFileViewer(false);
    }, []);

    // Extract files for the FileViewer.
    const files = useMemo(
        () => state.largeFiles.map((item) => item.file),
        [state.largeFiles],
    );

    const contents = (() => {
        switch (state.analysisStatus) {
            case undefined:
            case "started":
                return <Loading />;
            case "failed":
                return <LoadFailed />;
            case "completed":
                // Show empty state only if no files AND no deletion in progress
                if (
                    state.largeFiles.length === 0 &&
                    state.deleteProgress === undefined
                ) {
                    return <NoLargeFilesFound />;
                } else {
                    return (
                        <LargeFiles
                            largeFiles={state.largeFiles}
                            onToggleSelection={(index) =>
                                dispatch({ type: "toggleSelection", index })
                            }
                            onOpenViewer={handleOpenViewer}
                            selectedCount={state.selectedCount}
                            selectedSize={state.selectedSize}
                            deleteProgress={state.deleteProgress}
                            onDeleteFiles={handleDeleteFiles}
                            onSelectAll={() => dispatch({ type: "selectAll" })}
                            onDeselectAll={() =>
                                dispatch({ type: "deselectAll" })
                            }
                            filter={state.filter}
                        />
                    );
                }
        }
    })();

    return (
        <Stack sx={{ height: "100vh" }}>
            <Navbar
                filter={state.filter}
                onChangeFilter={(filter) =>
                    dispatch({ type: "changeFilter", filter })
                }
            />
            {contents}
            <FileViewer
                open={openFileViewer}
                onClose={handleCloseViewer}
                files={files}
                initialIndex={currentIndex}
                onVisualFeedback={() => {
                    // No-op: Large files viewer is read-only
                }}
            />
        </Stack>
    );
};

export default Page;

interface NavbarProps {
    filter: LargeFileFilter;
    onChangeFilter: (filter: LargeFileFilter) => void;
}

const Navbar: React.FC<NavbarProps> = ({ filter, onChangeFilter }) => {
    const router = useRouter();

    return (
        <Stack>
            <Stack
                direction="row"
                sx={(theme) => ({
                    alignItems: "center",
                    justifyContent: "space-between",
                    padding: "8px 4px",
                    borderBottom: `1px solid ${theme.vars.palette.divider}`,
                })}
            >
                <Box sx={{ minWidth: "100px" }}>
                    <IconButton onClick={router.back}>
                        <ArrowBackIcon />
                    </IconButton>
                </Box>
                <Typography variant="h6">{t("large_files_title")}</Typography>
                <Box sx={{ minWidth: "100px" }} />
            </Stack>
            <FilterChips {...{ filter, onChangeFilter }} />
        </Stack>
    );
};

interface FilterChipsProps {
    filter: LargeFileFilter;
    onChangeFilter: (filter: LargeFileFilter) => void;
}

const filterChipSx = (isSelected: boolean, hasIcon: boolean) => ({
    height: { xs: 28, sm: 32 },
    fontSize: { xs: "0.75rem", sm: "0.8125rem" },
    ...(hasIcon
        ? { pl: { xs: 1, sm: 1.5 }, pr: { xs: 0.5, sm: 1 } }
        : { px: { xs: 1, sm: 1.5 } }),
    ...(!isSelected && { backgroundColor: "rgba(255, 255, 255, 0.12)" }),
});

const FilterChips: React.FC<FilterChipsProps> = ({
    filter,
    onChangeFilter,
}) => (
    <Stack
        direction="row"
        sx={{ gap: 1, pl: 3, pr: 2, py: 4, flexWrap: "wrap" }}
    >
        <Chip
            label={t("all")}
            variant={filter === "all" ? "filled" : "outlined"}
            color={filter === "all" ? "primary" : "default"}
            onClick={() => onChangeFilter("all")}
            sx={filterChipSx(filter === "all", false)}
        />
        <Chip
            icon={<ImageIcon sx={{ fontSize: "18px !important" }} />}
            label={t("photos")}
            variant={filter === "photos" ? "filled" : "outlined"}
            color={filter === "photos" ? "primary" : "default"}
            onClick={() => onChangeFilter("photos")}
            sx={filterChipSx(filter === "photos", true)}
        />
        <Chip
            icon={<VideocamIcon sx={{ fontSize: "18px !important" }} />}
            label={t("videos")}
            variant={filter === "videos" ? "filled" : "outlined"}
            color={filter === "videos" ? "primary" : "default"}
            onClick={() => onChangeFilter("videos")}
            sx={filterChipSx(filter === "videos", true)}
        />
    </Stack>
);

const Loading: React.FC = () => (
    <CenteredFill>
        <ActivityIndicator />
    </CenteredFill>
);

const LoadFailed: React.FC = () => (
    <CenteredFill>
        <ActivityErrorIndicator />
    </CenteredFill>
);

const NoLargeFilesFound: React.FC = () => (
    <CenteredFill>
        <Typography sx={{ color: "text.muted", textAlign: "center" }}>
            {t("no_large_files")}
        </Typography>
    </CenteredFill>
);

interface LargeFilesProps {
    largeFiles: LargeFileItem[];
    onToggleSelection: (index: number) => void;
    onOpenViewer: (index: number) => void;
    selectedCount: number;
    selectedSize: number;
    deleteProgress: number | undefined;
    onDeleteFiles: () => void;
    onSelectAll: () => void;
    onDeselectAll: () => void;
    filter: LargeFileFilter;
}

const BOTTOM_BAR_HEIGHT = 64;

const LargeFiles: React.FC<LargeFilesProps> = ({
    largeFiles,
    onToggleSelection,
    onOpenViewer,
    selectedCount,
    selectedSize,
    deleteProgress,
    onDeleteFiles,
    onSelectAll,
    onDeselectAll,
    filter,
}) => (
    <Box sx={{ flex: 1, position: "relative", overflow: "hidden" }}>
        <Autosizer>
            {({ width, height }) => (
                <LargeFilesGrid
                    {...{
                        width,
                        height,
                        largeFiles,
                        onToggleSelection,
                        onOpenViewer,
                    }}
                />
            )}
        </Autosizer>
        <BottomBar
            {...{
                totalCount: largeFiles.length,
                selectedCount,
                selectedSize,
                deleteProgress,
                onDeleteFiles,
                onSelectAll,
                onDeselectAll,
                filter,
            }}
        />
    </Box>
);

interface LargeFilesGridProps {
    width: number;
    height: number;
    largeFiles: LargeFileItem[];
    onToggleSelection: (index: number) => void;
    onOpenViewer: (index: number) => void;
}

interface LargeFilesGridItemData {
    largeFiles: LargeFileItem[];
    onToggleSelection: (index: number) => void;
    onOpenViewer: (index: number) => void;
    layoutParams: ThumbnailGridLayoutParams;
    dataRowCount: number;
}

const LargeFilesGrid: React.FC<LargeFilesGridProps> = ({
    width,
    height,
    largeFiles,
    onToggleSelection,
    onOpenViewer,
}) => {
    const layoutParams = useMemo(
        () => computeThumbnailGridLayoutParams(width),
        [width],
    );

    const columns = layoutParams.columns;
    const dataRowCount = Math.ceil(largeFiles.length / columns);
    // Add an extra row for bottom padding (to account for the floating bar)
    const rowCount = dataRowCount + 1;

    const itemData: LargeFilesGridItemData = {
        largeFiles,
        onToggleSelection,
        onOpenViewer,
        layoutParams,
        dataRowCount,
    };

    const itemSize = (index: number) =>
        index === dataRowCount
            ? BOTTOM_BAR_HEIGHT
            : layoutParams.itemHeight + layoutParams.gap;

    const itemKey = (index: number) =>
        index === dataRowCount ? "padding" : `row-${index}`;

    // Key based on width to force re-render when layout changes
    const key = `${width}`;

    return (
        <VariableSizeList
            key={key}
            style={
                {
                    "--et-padding-inline": `${layoutParams.paddingInline}px`,
                } as React.CSSProperties
            }
            {...{
                height,
                width,
                itemData,
                itemCount: rowCount,
                itemSize,
                itemKey,
            }}
        >
            {GridRow}
        </VariableSizeList>
    );
};

const GridRow: React.FC<ListChildComponentProps<LargeFilesGridItemData>> = memo(
    ({ index: rowIndex, style, data }) => {
        const {
            largeFiles,
            onToggleSelection,
            onOpenViewer,
            layoutParams,
            dataRowCount,
        } = data;

        // Padding row at the end - render empty space
        if (rowIndex === dataRowCount) {
            return <div style={style} />;
        }

        const columns = layoutParams.columns;

        // Calculate which items are in this row
        const startIndex = rowIndex * columns;
        const endIndex = Math.min(startIndex + columns, largeFiles.length);
        const rowItems = largeFiles.slice(startIndex, endIndex);

        return (
            <ItemGrid layoutParams={layoutParams} style={style}>
                {rowItems.map((item, colIndex) => {
                    const itemIndex = startIndex + colIndex;
                    return (
                        <GridItem
                            key={item.id}
                            item={item}
                            onToggle={() => onToggleSelection(itemIndex)}
                            onOpen={() => onOpenViewer(itemIndex)}
                        />
                    );
                })}
            </ItemGrid>
        );
    },
    areEqual,
);

interface GridItemProps {
    item: LargeFileItem;
    onToggle: () => void;
    onOpen: () => void;
}

const LONG_PRESS_DURATION = 500;

const GridItem: React.FC<GridItemProps> = memo(({ item, onToggle, onOpen }) => {
    const checked = item.isSelected;
    const longPressTimer = React.useRef<ReturnType<typeof setTimeout> | null>(
        null,
    );
    const isLongPress = React.useRef(false);
    const onOpenRef = React.useRef(onOpen);
    useEffect(() => {
        onOpenRef.current = onOpen;
    }, [onOpen]);

    // Memoize touch device detection to avoid media query on every render
    const isTouchDevice = useMemo(
        () =>
            typeof window !== "undefined" &&
            window.matchMedia("(pointer: coarse)").matches,
        [],
    );

    // Cleanup timer on unmount to prevent memory leaks
    useEffect(() => {
        return () => {
            if (longPressTimer.current) {
                clearTimeout(longPressTimer.current);
            }
        };
    }, []);

    const handleCheckboxChange: React.ChangeEventHandler<HTMLInputElement> = (
        e,
    ) => {
        e.stopPropagation();
        onToggle();
    };

    const handleTouchStart = () => {
        isLongPress.current = false;
        longPressTimer.current = setTimeout(() => {
            isLongPress.current = true;
            onOpenRef.current();
        }, LONG_PRESS_DURATION);
    };

    const handleTouchEnd = () => {
        if (longPressTimer.current) {
            clearTimeout(longPressTimer.current);
            longPressTimer.current = null;
        }
    };

    const handleTouchMove = () => {
        if (longPressTimer.current) {
            clearTimeout(longPressTimer.current);
            longPressTimer.current = null;
        }
    };

    const handleClick = () => {
        if (isLongPress.current) return;

        // On mobile, tap to toggle selection; on desktop, tap to open
        if (isTouchDevice) {
            onToggle();
        } else {
            onOpen();
        }
    };

    return (
        <TileContainer
            onClick={handleClick}
            onTouchStart={handleTouchStart}
            onTouchEnd={handleTouchEnd}
            onTouchMove={handleTouchMove}
        >
            <ItemCard TileComponent={LargeFileTile} coverFile={item.file}>
                <LargeFileTileOverlay>
                    <SizeLabel className="size-label">
                        {formattedByteSize(item.size)}
                    </SizeLabel>
                </LargeFileTileOverlay>
            </ItemCard>
            <Check
                type="checkbox"
                checked={checked}
                onChange={handleCheckboxChange}
                onClick={(e) => e.stopPropagation()}
            />
            {checked && <SelectedOverlay />}
        </TileContainer>
    );
});

interface BottomBarProps {
    totalCount: number;
    selectedCount: number;
    selectedSize: number;
    deleteProgress: number | undefined;
    onDeleteFiles: () => void;
    onSelectAll: () => void;
    onDeselectAll: () => void;
    filter: LargeFileFilter;
}

const BottomBar: React.FC<BottomBarProps> = ({
    totalCount,
    selectedCount,
    selectedSize,
    deleteProgress,
    onDeleteFiles,
    onSelectAll,
    onDeselectAll,
    filter,
}) => {
    const allSelected = selectedCount === totalCount;

    const selectAllLabel = useMemo(() => {
        switch (filter) {
            case "photos":
                return t("select_all_photos");
            case "videos":
                return t("select_all_videos");
            default:
                return t("select_all");
        }
    }, [filter]);

    const deselectAllLabel = useMemo(() => {
        switch (filter) {
            case "photos":
                return t("deselect_all_photos");
            case "videos":
                return t("deselect_all_videos");
            default:
                return t("deselect_all");
        }
    }, [filter]);

    return (
        <Stack
            direction="row"
            sx={{
                position: "absolute",
                bottom: 0,
                left: 0,
                right: 0,
                height: BOTTOM_BAR_HEIGHT,
                gap: 1,
                alignItems: "center",
                justifyContent: "center",
                paddingBottom: 1,
            }}
        >
            <FocusVisibleButton
                sx={{
                    width: { xs: 150, sm: 170 },
                    fontSize: { xs: "0.85rem", sm: "0.9rem" },
                }}
                disabled={deleteProgress !== undefined}
                onClick={allSelected ? onDeselectAll : onSelectAll}
            >
                {allSelected ? deselectAllLabel : selectAllLabel}
            </FocusVisibleButton>
            <DeleteButton
                {...{
                    selectedCount,
                    selectedSize,
                    deleteProgress,
                    onDeleteFiles,
                }}
            />
        </Stack>
    );
};

interface DeleteButtonProps {
    selectedCount: number;
    selectedSize: number;
    deleteProgress: number | undefined;
    onDeleteFiles: () => void;
}

const DeleteButton: React.FC<DeleteButtonProps> = ({
    selectedCount,
    selectedSize,
    deleteProgress,
    onDeleteFiles,
}) => {
    const isDeleting = deleteProgress !== undefined;

    return (
        <FocusVisibleButton
            sx={(theme) => ({
                px: { xs: 2, sm: 3 },
                width: { xs: 220, sm: 260 },
                minHeight: { xs: 42, sm: 44 },
                fontSize: { xs: "0.85rem", sm: "0.9rem" },
                "&.Mui-disabled": isDeleting
                    ? {
                          // Keep critical color during deletion
                          backgroundColor: "critical.main",
                          color: "critical.contrastText",
                      }
                    : {
                          // Light mode default
                          backgroundColor: "rgba(0, 0, 0, 0.3)",
                          color: "rgba(0, 0, 0, 0.5)",
                          // Dark mode override
                          ...theme.applyStyles("dark", {
                              backgroundColor: "rgba(255, 255, 255, 0.3)",
                              color: "rgba(255, 255, 255, 0.5)",
                          }),
                      },
            })}
            disabled={selectedCount === 0 || isDeleting}
            color="critical"
            onClick={onDeleteFiles}
        >
            {isDeleting ? (
                <LinearProgress
                    sx={{ borderRadius: "4px", width: "100%" }}
                    variant={
                        deleteProgress === 0 ? "indeterminate" : "determinate"
                    }
                    value={deleteProgress}
                    color="inherit"
                />
            ) : (
                <Stack direction="row" sx={{ gap: 1, alignItems: "center" }}>
                    <Typography sx={{ fontSize: "inherit" }}>
                        {t("delete_files_button", { count: selectedCount })}
                    </Typography>
                    <Typography
                        sx={{ fontSize: "inherit", fontWeight: "regular" }}
                    >
                        ({formattedByteSize(selectedSize)})
                    </Typography>
                </Stack>
            )}
        </FocusVisibleButton>
    );
};

// --- Styled Components ---

interface ItemGridProps {
    layoutParams: ThumbnailGridLayoutParams;
    style?: React.CSSProperties;
}

const ItemGrid = styled("div", {
    shouldForwardProp: (prop) => prop !== "layoutParams",
})<ItemGridProps>(
    ({ layoutParams }) => `
    display: grid;
    padding-inline: ${layoutParams.paddingInline}px;
    grid-template-columns: repeat(${layoutParams.columns}, ${layoutParams.itemWidth}px);
    grid-auto-rows: ${layoutParams.itemHeight}px;
    gap: ${layoutParams.gap}px;
`,
);

const TileContainer = styled("div")`
    position: relative;
    cursor: pointer;
    border-radius: 4px;
    overflow: hidden;
    width: 100%;
    height: 100%;
    user-select: none;

    @media (pointer: fine) {
        &:hover {
            input[type="checkbox"] {
                visibility: visible;
            }
        }
    }
`;

const LargeFileTile = styled("div")`
    display: flex;
    position: relative;
    border-radius: 4px;
    overflow: hidden;
    width: 100%;
    height: 100%;
    & > img {
        object-fit: cover;
        width: 100%;
        height: 100%;
        pointer-events: none;
    }
`;

const SizeLabel = styled(Typography)`
    position: absolute;
    bottom: 0;
    left: 0;
    right: 0;
    background: linear-gradient(
        to top,
        rgba(0, 0, 0, 0.7) 0%,
        transparent 100%
    );
    color: white;
    padding: 16px 6px 6px;
    text-align: center;
    font-size: 0.75rem;
    font-weight: 500;
    border-radius: 0 0 4px 4px;

    @media (min-width: 600px) {
        padding: 25px 8px 12px;
        font-size: 1rem;
    }
`;

const Check = styled("input")(
    ({ theme }) => `
    appearance: none;
    -webkit-appearance: none;
    -moz-appearance: none;
    position: absolute;
    z-index: 10;
    top: 0;
    left: 0;
    outline: none;
    cursor: pointer;
    width: 31px;
    height: 31px;
    box-sizing: border-box;

    @media (pointer: coarse) {
        pointer-events: none;
    }

    &::before {
        content: "";
        display: block; /* Critical for Safari */
        width: 19px;
        height: 19px;
        background-color: ${theme.vars.palette.grey[300]};
        border-radius: 50%;
        margin: 6px;
        transition: background-color 0.3s ease, opacity 0.3s ease;
        position: relative; /* Important for Safari */
    }

    &::after {
        content: "";
        display: block; /* Critical for Safari */
        position: absolute;
        top: 50%;
        left: 50%;
        width: 5px;
        height: 11px;
        border: solid ${theme.vars.palette.grey[800]};
        border-width: 0 2px 2px 0;
        transform: translate(-50%, -60%) rotate(45deg);
        transition: border-color 0.3s ease, opacity 0.3s ease;
        transform-origin: center;
    }

    /* Default state - hidden */
    visibility: hidden;

    /* Hover state - show with reduced opacity */
    &:hover {
        visibility: visible;
        opacity: 0.7;
    }

    /* Checked state - fully visible and colored */
    &:checked {
        visibility: visible;
        opacity: 1 !important;
    }

    &:checked::before {
        background-color: ${theme.vars.palette.accent.main};
    }

    &:checked::after {
        border-color: ${theme.vars.palette.grey[300]};
    }
`,
);

const SelectedOverlay = styled(Overlay)(
    ({ theme }) => `
    border: 2px solid ${theme.vars.palette.accent.main};
    border-radius: 4px;
    pointer-events: none;
`,
);
