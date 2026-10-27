import {
    deleteSelectedLargeFiles,
    findLargeFiles,
    largeFilesInitialState,
    largeFilesReducer,
    MIN_LARGE_FILE_SIZE,
    type LargeFileFilter,
    type LargeFileItem,
} from "@/services/large-files";
import { Box, LinearProgress, Stack, styled, Typography } from "@mui/material";
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
import type { ThumbnailGridLayoutParams } from "ente-new/photos/components/utils/thumbnail-grid-layout";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
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

interface LargeFilesViewProps {
    onRemoteFilesPull: () => Promise<void>;
}

export function LargeFilesView({ onRemoteFilesPull }: LargeFilesViewProps) {
    const { showMiniDialog, onGenericError } = useBaseContext();
    const { setIsFileViewerOpen } = usePhotosAppContext();

    const [state, dispatch] = useReducer(
        largeFilesReducer,
        largeFilesInitialState,
    );
    const [openFileViewer, setOpenFileViewer] = useState(false);
    const [currentIndex, setCurrentIndex] = useState(0);

    useEffect(() => {
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
                        onRemoteFilesPull,
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
    }, [showMiniDialog, onGenericError, state.largeFiles, onRemoteFilesPull]);

    const handleOpenViewer = useCallback(
        (index: number) => {
            setCurrentIndex(index);
            setOpenFileViewer(true);
            setIsFileViewerOpen?.(true);
        },
        [setIsFileViewerOpen],
    );

    const handleCloseViewer = useCallback(() => {
        setOpenFileViewer(false);
        setIsFileViewerOpen?.(false);
    }, [setIsFileViewerOpen]);

    useEffect(() => () => setIsFileViewerOpen?.(false), [setIsFileViewerOpen]);

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
        <Stack
            sx={{
                flex: 1,
                minWidth: 0,
                minHeight: 0,
                px: { xs: 2, md: "36px" },
                pb: { xs: 2, md: "36px" },
                pt: 0,
                gap: 3,
            }}
        >
            <Navbar
                largeFiles={state.largeFiles}
                analysisCompleted={state.analysisStatus === "completed"}
                disabled={state.deleteProgress !== undefined}
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
                    // The large-files viewer is read-only.
                }}
            />
        </Stack>
    );
}

interface NavbarProps {
    largeFiles: LargeFileItem[];
    analysisCompleted: boolean;
    disabled: boolean;
    filter: LargeFileFilter;
    onChangeFilter: (filter: LargeFileFilter) => void;
}

const Navbar: React.FC<NavbarProps> = ({
    largeFiles,
    analysisCompleted,
    disabled,
    filter,
    onChangeFilter,
}) => {
    const totalSize = useMemo(
        () => largeFiles.reduce((sum, item) => sum + item.size, 0),
        [largeFiles],
    );
    return (
        <Stack
            direction={{ xs: "column", sm: "row" }}
            sx={{
                gap: 2,
                justifyContent: "space-between",
                alignItems: { sm: "center" },
            }}
        >
            <Stack sx={{ gap: "2px" }}>
                <Typography
                    component="h1"
                    sx={{
                        fontFamily: '"Outfit Variable", sans-serif',
                        fontSize: 24,
                        lineHeight: "32px",
                        fontWeight: 600,
                    }}
                >
                    {t("large_files_title")}
                </Typography>
                {analysisCompleted && (
                    <Typography
                        sx={{
                            color: "text.muted",
                            fontSize: 13,
                            lineHeight: "19px",
                            fontWeight: 400,
                        }}
                    >
                        {t("large_files_summary", {
                            count: largeFiles.length,
                            threshold: formattedByteSize(MIN_LARGE_FILE_SIZE),
                            size: formattedByteSize(totalSize),
                        })}
                    </Typography>
                )}
            </Stack>
            <Stack
                direction="row"
                sx={{ gap: 1, alignItems: "center", flexWrap: "wrap" }}
            >
                <FilterChips {...{ filter, onChangeFilter, disabled }} />
            </Stack>
        </Stack>
    );
};

interface FilterChipsProps {
    filter: LargeFileFilter;
    onChangeFilter: (filter: LargeFileFilter) => void;
    disabled: boolean;
}

const FilterChips: React.FC<FilterChipsProps> = ({
    filter,
    onChangeFilter,
    disabled,
}) => (
    <Stack direction="row" sx={{ gap: 1 }}>
        {(["all", "photos", "videos"] as const).map((value) => (
            <FocusVisibleButton
                key={value}
                variant="text"
                disabled={disabled}
                aria-pressed={filter === value}
                onClick={() => onChangeFilter(value)}
                sx={{
                    minWidth: 0,
                    height: 40,
                    px: "18px",
                    gap: "4px",
                    borderRadius: "24px",
                    fontSize: 12,
                    lineHeight: "16px",
                    fontWeight: 500,
                    backgroundColor:
                        filter === value ? "text.base" : "transparent",
                    color: filter === value ? "background.paper" : "text.muted",
                    "&:hover": {
                        backgroundColor:
                            filter === value ? "text.base" : "fill.faint",
                    },
                }}
            >
                {t(value)}
            </FocusVisibleButton>
        ))}
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
    <Box
        sx={{
            flex: 1,
            minWidth: 0,
            minHeight: 0,
            position: "relative",
            overflow: "hidden",
        }}
    >
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
    const layoutParams = useMemo(() => {
        const gap = 4;
        const isSmallerLayout = width < 600;
        const targetItemWidth = isSmallerLayout ? 120 : 200;
        const columns = Math.max(
            2,
            Math.floor((width + gap) / (targetItemWidth + gap)),
        );
        const itemWidth = Math.max(0, (width - (columns - 1) * gap) / columns);
        return {
            containerWidth: width,
            isSmallerLayout,
            paddingInline: 0,
            columns,
            itemWidth,
            itemHeight: itemWidth,
            gap,
        };
    }, [width]);

    const columns = layoutParams.columns;
    const dataRowCount = Math.ceil(largeFiles.length / columns);
    // Reserve a final row for the floating bar.
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

    // react-window must remount when the layout width changes.
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

        if (rowIndex === dataRowCount) {
            return <div style={style} />;
        }

        const columns = layoutParams.columns;

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

    const isTouchDevice = useMemo(
        () =>
            typeof window !== "undefined" &&
            window.matchMedia("(pointer: coarse)").matches,
        [],
    );

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
                aria-label={t("select_file", {
                    filename: item.file.metadata.title,
                })}
                checked={checked}
                onChange={handleCheckboxChange}
                onClick={(e) => e.stopPropagation()}
                onTouchStart={(e) => e.stopPropagation()}
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
                          backgroundColor: "critical.main",
                          color: "critical.contrastText",
                      }
                    : {
                          backgroundColor: "rgba(0, 0, 0, 0.3)",
                          color: "rgba(0, 0, 0, 0.5)",
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
    bottom: 8px;
    left: 8px;
    background: rgba(0, 0, 0, 0.8);
    color: white;
    padding: 3px 8px;
    font-size: 12px;
    line-height: 16px;
    font-weight: 500;
    border-radius: 35px;
`;

// Safari requires block-level positioned pseudo-elements here.
const Check = styled("input")(
    ({ theme }) => `
    appearance: none;
    position: absolute;
    z-index: 10;
    top: 0;
    right: 0;
    margin: 0;
    cursor: pointer;
    width: 32px;
    height: 32px;
    box-sizing: border-box;
    &::before {
        content: "";
        display: block;
        position: absolute;
        inset: 8px;
        border: 1px solid ${theme.vars.palette.text.muted};
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.15);
    }
    &:checked::before {
        background: ${theme.vars.palette.accent.main};
        border-color: ${theme.vars.palette.accent.main};
    }
    &:checked::after {
        content: "";
        position: absolute;
        top: 50%;
        left: 50%;
        width: 4px;
        height: 8px;
        border: solid white;
        border-width: 0 1.5px 1.5px 0;
        transform: translate(-50%, -60%) rotate(45deg);
    }
    &:focus-visible {
        outline: 2px solid ${theme.vars.palette.accent.main};
        outline-offset: -2px;
        border-radius: 4px;
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
