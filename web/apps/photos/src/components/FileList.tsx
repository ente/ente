import Avatar from "@/components/Avatar";
import {
    FileContextMenu,
    type ContextMenuPosition,
} from "@/components/FileContextMenu";
import type { GalleryBarMode } from "@/components/gallery/reducer";
import { StarIcon } from "@/components/icons/StarIcon";
import {
    selectedFavoriteCount as countSelectedFavorites,
    type SelectedState,
} from "@/utils/file";
import {
    getAvailableFileActions,
    type FileContextAction,
} from "@/utils/file-actions";
import {
    handleSelectCreator,
    handleSelectCreatorMulti,
} from "@/utils/photoFrame";
import AlbumOutlinedIcon from "@mui/icons-material/AlbumOutlined";
import KeyboardArrowUpIcon from "@mui/icons-material/KeyboardArrowUp";
import PlayArrowRoundedIcon from "@mui/icons-material/PlayArrowRounded";
import PlayCircleOutlineOutlinedIcon from "@mui/icons-material/PlayCircleOutlineOutlined";
import { Box, Checkbox, Fab, Typography, styled } from "@mui/material";
import type { LocalUser } from "ente-accounts/services/user";
import { assertionFailed } from "ente-base/assert";
import { Overlay } from "ente-base/components/containers";
import { formattedDateRelative } from "ente-base/i18n-date";
import log from "ente-base/log";
import { downloadManager } from "ente-gallery/services/download";
import type { EnteFile } from "ente-media/file";
import { fileDurationString } from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import {
    LoadingThumbnail,
    StaticThumbnail,
} from "ente-new/photos/components/PlaceholderThumbnails";
import { TileBottomTextOverlay } from "ente-new/photos/components/Tiles";
import {
    computeThumbnailGridLayoutParams,
    thumbnailGap,
    type ThumbnailGridLayoutParams,
} from "ente-new/photos/components/utils/thumbnail-grid-layout";
import {
    PseudoCollectionID,
    type CollectionSummary,
} from "ente-new/photos/services/collection-summary";
import { batch } from "ente-utils/array";
import { t } from "i18next";
import React, {
    memo,
    useCallback,
    useDeferredValue,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";
import {
    VariableSizeList,
    areEqual,
    type ListChildComponentProps,
} from "react-window";

export interface FileListHeaderOrFooter {
    component: React.ReactNode;
    height: number;
    extendToInlineEdges?: boolean;
}

type FileListItem =
    | {
          type: "file";
          height: number;
          groups: {
              annotatedFiles: FileListAnnotatedFile[];
              annotatedFilesStartIndex: number;
          }[];
      }
    | {
          type: "date";
          height: number;
          groups: { date: string; dateSpan: number }[];
      }
    | {
          type: "span";
          height: number;
          component: React.ReactNode;
          extendToInlineEdges?: boolean;
      };

export interface FileListAnnotatedFile {
    file: EnteFile;
    timelineDateString: string;
}

// deleteBy is an epoch-microsecond timestamp.
type EnteTrashFile = EnteFile & { deleteBy?: number };

export interface FileListProps {
    height: number;
    width: number;
    listBorderRadius?: string;
    annotatedFiles: FileListAnnotatedFile[];
    mode?: GalleryBarMode;
    modePlus?: GalleryBarMode | "search";
    header?: FileListHeaderOrFooter;
    footer?: FileListHeaderOrFooter;
    user?: LocalUser;
    disableGrouping?: boolean;
    enableSelect?: boolean;
    setSelected: (
        selected: SelectedState | ((selected: SelectedState) => SelectedState),
    ) => void;
    selected: SelectedState;
    activeCollectionID: number;
    activePersonID?: string | undefined;
    favoriteFileIDs?: Set<number>;
    emailByUserID?: Map<number, string>;
    onItemClick: (index: number) => void;
    onScroll?: (scrollOffset: number) => void;
    onVisibleDateChange?: (date: string | undefined) => void;
    collectionSummary?: CollectionSummary;
    onContextMenuAction?: (
        action: FileContextAction,
        targetFile?: EnteFile,
        meta?: { isEphemeralSingleSelection: boolean },
    ) => void;
    showAddPersonAction?: boolean;
    showEditLocationAction?: boolean;
    onContextMenuOpenChange?: (open: boolean) => void;
    suppressSelectionUI?: boolean;
}

export const FileList: React.FC<FileListProps> = ({
    height,
    width,
    listBorderRadius,
    mode,
    modePlus,
    header,
    footer,
    user,
    annotatedFiles,
    disableGrouping,
    enableSelect,
    selected,
    setSelected,
    activeCollectionID,
    activePersonID,
    favoriteFileIDs,
    emailByUserID,
    onItemClick,
    onScroll,
    onVisibleDateChange,
    collectionSummary,
    onContextMenuAction,
    showAddPersonAction,
    showEditLocationAction,
    onContextMenuOpenChange,
    suppressSelectionUI = false,
}) => {
    const [_items, setItems] = useState<FileListItem[]>([]);
    const items = useDeferredValue(_items);

    const [rangeStartIndex, setRangeStartIndex] = useState<number | undefined>(
        undefined,
    );
    const [hoverIndex, setHoverIndex] = useState<number | undefined>(undefined);
    const [isShiftKeyPressed, setIsShiftKeyPressed] = useState(false);
    const [checkedTimelineDateStrings, setCheckedTimelineDateStrings] =
        useState(new Set<string>());
    const [showBackToTop, setShowBackToTop] = useState(false);

    const [contextMenu, setContextMenu] = useState<{
        position: ContextMenuPosition;
        file: EnteFile;
        fileIndex: number;
    } | null>(null);

    // Right-click temporarily replaces selection; restore it if no action runs.
    const previousSelectionRef = useRef<SelectedState | null>(null);
    const contextMenuActionTakenRef = useRef(false);

    const listRef = useRef<VariableSizeList | null>(null);
    const outerRef = useRef<HTMLDivElement | null>(null);

    const layoutParams = useMemo(
        () => computeThumbnailGridLayoutParams(width),
        [width],
    );

    useEffect(() => {
        // Defer resize-heavy list rebuilds so React can discard stale renders.
        let items: FileListItem[] = [];

        if (header) items.push(asFullSpanFileListItem(header));

        const { isSmallerLayout, columns } = layoutParams;
        const fileItemHeight = layoutParams.itemHeight + layoutParams.gap;
        if (disableGrouping) {
            items = items.concat(
                batch(annotatedFiles, columns).map(
                    (batchFiles, batchIndex) => ({
                        height: fileItemHeight,
                        type: "file",
                        groups: [
                            {
                                annotatedFiles: batchFiles,
                                annotatedFilesStartIndex: batchIndex * columns,
                            },
                        ],
                    }),
                ),
            );
        } else {
            let fileIndex = 0;
            const createFileItem = (splits: FileListAnnotatedFile[][]) =>
                ({
                    height: fileItemHeight,
                    type: "file",
                    groups: splits.map((split) => {
                        const group = {
                            annotatedFiles: split,
                            annotatedFilesStartIndex: fileIndex,
                        };
                        fileIndex += split.length;
                        return group;
                    }),
                }) satisfies FileListItem;

            const pushItemsFromSplits = (splits: FileListAnnotatedFile[][]) => {
                if (splits.length > 1) {
                    items.push({
                        height: dateListItemHeight,
                        type: "date",
                        groups: splits.map((s) => ({
                            date: s[0]!.timelineDateString,
                            dateSpan: s.length,
                        })),
                    });
                    items.push(createFileItem(splits));
                } else {
                    items.push({
                        height: dateListItemHeight,
                        type: "date",
                        groups: splits.map((s) => ({
                            date: s[0]!.timelineDateString,
                            dateSpan: columns,
                        })),
                    });
                    items = items.concat(
                        batch(splits[0]!, columns).map((batchFiles) =>
                            createFileItem([batchFiles]),
                        ),
                    );
                }
            };

            const spaceBetweenDatesToImageContainerWidthRatio = 0.244;

            let pendingSplits = new Array<FileListAnnotatedFile[]>();
            for (const split of splitByDate(annotatedFiles)) {
                const filledColumns = pendingSplits.reduce(
                    (a, s) => a + s.length,
                    0,
                );
                const incomingColumns = split.length;

                if (
                    !isSmallerLayout &&
                    filledColumns +
                        incomingColumns +
                        Math.ceil(
                            pendingSplits.length *
                                spaceBetweenDatesToImageContainerWidthRatio,
                        ) <=
                        columns
                ) {
                    pendingSplits.push(split);
                    continue;
                }

                if (pendingSplits.length) pushItemsFromSplits(pendingSplits);
                pendingSplits = [split];
            }
            if (pendingSplits.length) pushItemsFromSplits(pendingSplits);
        }

        if (!annotatedFiles.length) {
            items.push({
                height: height - 48,
                type: "span",
                component: (
                    <NoFilesListItem>
                        <Typography sx={{ color: "text.faint" }}>
                            {t("nothing_here")}
                        </Typography>
                    </NoFilesListItem>
                ),
            });
        }

        let leftoverHeight = height - (footer?.height ?? 0);
        for (const item of items) {
            leftoverHeight -= item.height;
            if (leftoverHeight <= 0) break;
        }
        if (leftoverHeight > 0) {
            items.push({
                height: leftoverHeight,
                type: "span",
                component: <></>,
            });
        }

        if (footer) items.push(asFullSpanFileListItem(footer));

        setItems(items);
    }, [
        width,
        height,
        header,
        footer,
        annotatedFiles,
        disableGrouping,
        layoutParams,
    ]);

    useEffect(() => {
        listRef.current?.resetAfterIndex(0);
    }, [items]);

    useEffect(() => {
        const notSelectedFiles = annotatedFiles.filter(
            (af) => !selected[af.file.id],
        );

        const unselectedDates = new Set(
            notSelectedFiles.map((af) => af.timelineDateString),
        );

        const localSelectedFiles = annotatedFiles.filter(
            (af) => !unselectedDates.has(af.timelineDateString),
        );

        const localSelectedDates = new Set(
            localSelectedFiles.map((af) => af.timelineDateString),
        );

        setCheckedTimelineDateStrings((prev) => {
            const checked = new Set(prev);
            unselectedDates.forEach((date) => checked.delete(date));
            localSelectedDates.forEach((date) => checked.add(date));
            return checked;
        });
    }, [annotatedFiles, selected]);

    const handleSelectMulti = useMemo(
        () =>
            handleSelectCreatorMulti(
                setSelected,
                mode,
                user?.id,
                activeCollectionID,
                activePersonID,
            ),
        [setSelected, mode, user?.id, activeCollectionID, activePersonID],
    );

    const onChangeSelectAllCheckBox = useCallback(
        (date: string) => {
            const next = new Set(checkedTimelineDateStrings);
            let isDateSelected: boolean;
            if (!next.has(date)) {
                next.add(date);
                isDateSelected = true;
            } else {
                next.delete(date);
                isDateSelected = false;
            }
            setCheckedTimelineDateStrings(next);

            const filesOnADay = annotatedFiles.filter(
                (af) => af.timelineDateString === date,
            );

            handleSelectMulti(filesOnADay.map((af) => af.file))(isDateSelected);
        },
        [annotatedFiles, checkedTimelineDateStrings, handleSelectMulti],
    );

    const handleSelect = useMemo(
        () =>
            handleSelectCreator(
                setSelected,
                mode,
                user?.id,
                activeCollectionID,
                activePersonID,
                setRangeStartIndex,
            ),
        [setSelected, mode, user?.id, activeCollectionID, activePersonID],
    );

    const isSelectionContextMatching = useMemo(() => {
        if (!mode) return selected.collectionID === activeCollectionID;
        if (mode !== selected.context?.mode) return false;
        if (selected.context.mode === "people") {
            return selected.context.personID === activePersonID;
        }
        return selected.context.collectionID === activeCollectionID;
    }, [activeCollectionID, activePersonID, mode, selected]);

    const isFileSelected = useCallback(
        (file: EnteFile) => {
            if (suppressSelectionUI) return false;
            return isSelectionContextMatching && !!selected[file.id];
        },
        [isSelectionContextMatching, selected, suppressSelectionUI],
    );

    const handleRangeSelect = useCallback(
        (index: number) => {
            if (rangeStartIndex === undefined || rangeStartIndex == index)
                return;

            const direction = index > rangeStartIndex ? 1 : -1;
            let checked = true;
            for (
                let i = rangeStartIndex;
                (index - i) * direction >= 0;
                i += direction
            ) {
                checked = checked && !!selected[annotatedFiles[i]!.file.id];
            }
            for (
                let i = rangeStartIndex;
                (index - i) * direction > 0;
                i += direction
            ) {
                handleSelect(annotatedFiles[i]!.file)(!checked);
            }
            handleSelect(annotatedFiles[index]!.file, index)(!checked);
        },
        [annotatedFiles, selected, rangeStartIndex, handleSelect],
    );

    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.key == "Shift") {
                setIsShiftKeyPressed(true);
            }
        };

        const handleKeyUp = (e: KeyboardEvent) => {
            if (e.key == "Shift") {
                setIsShiftKeyPressed(false);
            }
        };

        document.addEventListener("keydown", handleKeyDown);
        document.addEventListener("keyup", handleKeyUp);

        return () => {
            document.removeEventListener("keydown", handleKeyDown);
            document.removeEventListener("keyup", handleKeyUp);
        };
    }, []);

    useEffect(() => {
        if (selected.count == 0) setRangeStartIndex(undefined);
    }, [selected]);

    const selectedFavoriteCount = useMemo(
        () => countSelectedFavorites(selected, favoriteFileIDs),
        [favoriteFileIDs, selected],
    );

    const contextMenuActions = useMemo(() => {
        if (!onContextMenuAction || !contextMenu) return [];
        const isTemporarySingleSelection =
            previousSelectionRef.current !== null;
        let selectionCount: number;
        let favoriteCount: number;
        let hasOnlyOwnFiles: boolean;

        if (isTemporarySingleSelection) {
            selectionCount = 1;
            favoriteCount = favoriteFileIDs?.has(contextMenu.file.id) ? 1 : 0;
            hasOnlyOwnFiles = contextMenu.file.ownerID === user?.id;
        } else {
            selectionCount = selected.count;
            favoriteCount = selectedFavoriteCount;
            hasOnlyOwnFiles =
                selectionCount > 0 && selected.ownCount === selectionCount;
        }
        const actions = getAvailableFileActions({
            barMode: mode,
            isInSearchMode: modePlus === "search",
            collectionSummary,
            hasOnlyOwnFiles,
            showAddPerson: !!showAddPersonAction,
            showEditLocation: !!showEditLocationAction && hasOnlyOwnFiles,
        });
        if (!actions.includes("favorite")) return actions;
        if (favoriteCount > 0 && favoriteCount < selectionCount) {
            return actions.filter(
                (action) => action !== "favorite" && action !== "unfavorite",
            );
        }
        if (favoriteCount === selectionCount && selectionCount > 0) {
            return actions.map((action) =>
                action === "favorite" ? "unfavorite" : action,
            );
        }
        return actions;
    }, [
        onContextMenuAction,
        contextMenu,
        mode,
        modePlus,
        collectionSummary,
        showAddPersonAction,
        showEditLocationAction,
        favoriteFileIDs,
        user?.id,
        selected.ownCount,
        selectedFavoriteCount,
        selected.count,
    ]);

    const handleContextMenu = useCallback(
        (event: React.MouseEvent, file: EnteFile, fileIndex: number) => {
            if (!onContextMenuAction) return;

            event.preventDefault();
            event.stopPropagation();

            previousSelectionRef.current = null;
            contextMenuActionTakenRef.current = false;
            if (!selected[file.id]) {
                previousSelectionRef.current = { ...selected };

                const isOwnFile = file.ownerID === user?.id;
                const context =
                    mode === "people" && activePersonID
                        ? { mode: "people" as const, personID: activePersonID }
                        : {
                              mode: (mode ?? "albums") as
                                  | "albums"
                                  | "hidden-albums"
                                  | "archive-albums",
                              collectionID: activeCollectionID,
                          };
                setSelected({
                    [file.id]: true,
                    ownCount: isOwnFile ? 1 : 0,
                    count: 1,
                    collectionID: activeCollectionID,
                    context,
                });
            }

            setContextMenu({
                position: { top: event.clientY, left: event.clientX },
                file,
                fileIndex,
            });
            onContextMenuOpenChange?.(true);
        },
        [
            onContextMenuAction,
            onContextMenuOpenChange,
            selected,
            setSelected,
            user,
            activeCollectionID,
            activePersonID,
            mode,
        ],
    );

    const handleContextMenuClose = useCallback(() => {
        // Menu close precedes item click, so restoration must wait a microtask.
        void Promise.resolve().then(() => {
            if (
                !contextMenuActionTakenRef.current &&
                previousSelectionRef.current
            ) {
                setSelected(previousSelectionRef.current);
            }
            previousSelectionRef.current = null;
            contextMenuActionTakenRef.current = false;
        });

        setContextMenu(null);
        onContextMenuOpenChange?.(false);
    }, [onContextMenuOpenChange, setSelected]);

    const handleContextMenuActionWithTracking = useCallback(
        (action: FileContextAction) => {
            const isEphemeralSingleSelection =
                previousSelectionRef.current?.count === 0;
            contextMenuActionTakenRef.current = true;
            onContextMenuAction?.(action, contextMenu?.file, {
                isEphemeralSingleSelection,
            });
        },
        [onContextMenuAction, contextMenu],
    );

    const renderListItem = useCallback(
        (item: FileListItem, isScrolling: boolean) => {
            const haveSelection =
                !!enableSelect && !suppressSelectionUI && selected.count > 0;
            const showGroupCheckbox =
                haveSelection && !(contextMenu && selected.count === 1);
            switch (item.type) {
                case "date":
                    return intersperseWithGaps(
                        item.groups,
                        ({ date, dateSpan }) => [
                            <DateListItem key={date} span={dateSpan}>
                                {showGroupCheckbox && (
                                    <Checkbox
                                        key={date}
                                        name={date}
                                        checked={checkedTimelineDateStrings.has(
                                            date,
                                        )}
                                        onChange={() =>
                                            onChangeSelectAllCheckBox(date)
                                        }
                                        size="small"
                                        sx={{ pl: 0 }}
                                    />
                                )}
                                {date}
                            </DateListItem>,
                        ],
                        ({ date }) => <div key={`${date}-gap`} />,
                    );
                case "file":
                    return intersperseWithGaps(
                        item.groups,
                        ({ annotatedFiles, annotatedFilesStartIndex }) =>
                            annotatedFiles.map((annotatedFile, j) => {
                                const file = annotatedFile.file;
                                const index = annotatedFilesStartIndex + j;
                                return (
                                    <FileThumbnail
                                        key={`tile-${file.id}-selected-${selected[file.id] ?? false}`}
                                        {...{
                                            user,
                                            emailByUserID,
                                            enableSelect:
                                                !!enableSelect &&
                                                !suppressSelectionUI,
                                        }}
                                        file={file}
                                        selected={isFileSelected(file)}
                                        selectOnClick={haveSelection}
                                        isRangeSelectActive={
                                            isShiftKeyPressed && haveSelection
                                        }
                                        isInSelectRange={
                                            rangeStartIndex !== undefined &&
                                            hoverIndex !== undefined &&
                                            ((index >= rangeStartIndex &&
                                                index <= hoverIndex) ||
                                                (index >= hoverIndex &&
                                                    index <= rangeStartIndex))
                                        }
                                        activeCollectionID={activeCollectionID}
                                        showPlaceholder={isScrolling}
                                        isFav={!!favoriteFileIDs?.has(file.id)}
                                        onClick={() => onItemClick(index)}
                                        onSelect={handleSelect(file, index)}
                                        onHover={() => setHoverIndex(index)}
                                        onRangeSelect={() =>
                                            handleRangeSelect(index)
                                        }
                                        onContextMenu={
                                            onContextMenuAction
                                                ? (e) =>
                                                      handleContextMenu(
                                                          e,
                                                          file,
                                                          index,
                                                      )
                                                : undefined
                                        }
                                    />
                                );
                            }),
                        ({ annotatedFilesStartIndex }) => (
                            <div key={`${annotatedFilesStartIndex}-gap`} />
                        ),
                    );
                case "span":
                    return item.component;
            }
        },
        [
            activeCollectionID,
            checkedTimelineDateStrings,
            contextMenu,
            emailByUserID,
            favoriteFileIDs,
            handleContextMenu,
            handleRangeSelect,
            handleSelect,
            hoverIndex,
            isShiftKeyPressed,
            isFileSelected,
            onChangeSelectAllCheckBox,
            onContextMenuAction,
            onItemClick,
            rangeStartIndex,
            enableSelect,
            selected,
            suppressSelectionUI,
            user,
        ],
    );

    const itemData = useMemo(
        () => ({ items, layoutParams, renderListItem }),
        [items, layoutParams, renderListItem],
    );

    const itemSize = useCallback(
        (index: number) => itemData.items[index]!.height,
        [itemData],
    );

    const itemKey = useCallback((index: number, itemData: FileListItemData) => {
        const item = itemData.items[index]!;
        switch (item.type) {
            case "date":
                return `date-${item.groups[0]!.date}-${index}`;
            case "file":
                return `file-${item.groups[0]!.annotatedFilesStartIndex}-${index}`;
            case "span":
                return `span-${index}`;
        }
    }, []);

    const lastVisibleDateRef = useRef<string | undefined>(undefined);

    const handleScroll = useCallback(
        ({ scrollOffset }: { scrollOffset: number }) => {
            onScroll?.(scrollOffset);

            setShowBackToTop(scrollOffset > 500);

            if (onVisibleDateChange && items.length > 0) {
                let cumulativeHeight = 0;
                let currentDate: string | undefined;

                for (const item of items) {
                    if (item.type === "date") {
                        currentDate = item.groups[0]?.date;
                    }
                    cumulativeHeight += item.height;
                    if (cumulativeHeight > scrollOffset) {
                        break;
                    }
                }

                if (currentDate !== lastVisibleDateRef.current) {
                    lastVisibleDateRef.current = currentDate;
                    onVisibleDateChange(currentDate);
                }
            }
        },
        [onScroll, onVisibleDateChange, items],
    );

    const handleScrollToTop = useCallback(() => {
        outerRef.current?.scrollTo({ top: 0, behavior: "smooth" });
    }, []);

    if (!items.length) {
        return <></>;
    }

    // A new key resets virtualization state when the view changes.
    let key = `${activeCollectionID}`;
    if (modePlus) {
        if (modePlus == "search") {
            key = "search";
        } else if (modePlus == "people") {
            if (!activePersonID) {
                assertionFailed();
            } else {
                key = activePersonID;
            }
        }
    }

    return (
        <Box sx={{ position: "relative", width, height }}>
            <VariableSizeList
                key={key}
                ref={listRef}
                outerRef={outerRef}
                {...{ width, height, itemData, itemSize, itemKey }}
                itemCount={items.length}
                overscanCount={3}
                useIsScrolling
                onScroll={handleScroll}
                style={
                    listBorderRadius
                        ? { borderRadius: listBorderRadius }
                        : undefined
                }
            >
                {FileListRow}
            </VariableSizeList>
            {showBackToTop && (
                <BackToTopButton
                    size="small"
                    aria-label="scroll to top"
                    onClick={handleScrollToTop}
                >
                    <KeyboardArrowUpIcon />
                </BackToTopButton>
            )}
            {onContextMenuAction && (
                <FileContextMenu
                    open={contextMenu !== null}
                    anchorPosition={contextMenu?.position}
                    onClose={handleContextMenuClose}
                    actions={contextMenuActions}
                    onAction={handleContextMenuActionWithTracking}
                />
            )}
        </Box>
    );
};

const splitByDate = (annotatedFiles: FileListAnnotatedFile[]) =>
    annotatedFiles.reduce(
        (splits, annotatedFile) => (
            splits.at(-1)?.at(0)?.timelineDateString ==
            annotatedFile.timelineDateString
                ? splits.at(-1)?.push(annotatedFile)
                : splits.push([annotatedFile]),
            splits
        ),
        new Array<FileListAnnotatedFile[]>(),
    );

const intersperseWithGaps = <T, U>(
    xs: T[],
    f: (x: T) => U[],
    g: (x: T) => U,
) => {
    const ys = xs.map((x) => [...f(x), g(x)]).flat();
    return ys.slice(0, ys.length - 1);
};

const FullSpanListItem = styled("div")`
    display: flex;
    align-items: center;
`;

const NoFilesListItem = styled(FullSpanListItem)`
    min-height: 100%;
    justify-content: center;
`;

const BackToTopButton = styled(Fab)(({ theme }) => ({
    position: "absolute",
    bottom: 24,
    right: 24,
    backgroundColor: theme.vars.palette.fill.faint,
    color: theme.vars.palette.text.base,
    boxShadow: "none",
    "&:hover": { backgroundColor: theme.vars.palette.fill.faintHover },
    [theme.breakpoints.down("sm")]: { display: "none" },
}));

const asFullSpanFileListItem = ({
    component,
    ...rest
}: FileListHeaderOrFooter): FileListItem => ({
    ...rest,
    type: "span",
    component: <FullSpanListItem>{component}</FullSpanListItem>,
});

const GridSpanListItem = styled("div")<{ span: number }>`
    grid-column: span ${({ span }) => span};
    display: flex;
    align-items: center;
`;

const dateListItemHeight = 48;

const DateListItem = styled(GridSpanListItem)(
    ({ theme }) => `
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    height: ${dateListItemHeight}px;
    color: ${theme.vars.palette.text.muted};
`,
);

interface FileListItemData {
    items: FileListItem[];
    layoutParams: ThumbnailGridLayoutParams;
    renderListItem: (
        item: FileListItem,
        isScrolling: boolean,
    ) => React.ReactNode;
}

const FileListRow = memo(
    ({
        index,
        style,
        isScrolling,
        data,
    }: ListChildComponentProps<FileListItemData>) => {
        const { items, layoutParams, renderListItem } = data;
        const { itemWidth, paddingInline, gap } = layoutParams;

        const item = items[index]!;
        const itemSpans = (() => {
            switch (item.type) {
                case "date":
                    return item.groups.map((g) => g.dateSpan);
                case "file":
                    return item.groups.map((g) => g.annotatedFiles.length);
                case "span":
                    return [];
            }
        })();
        const px =
            item.type == "span" && item.extendToInlineEdges ? 0 : paddingInline;

        return (
            <Box
                style={style}
                sx={[
                    { width: "100%", paddingInline: `${px}px` },
                    itemSpans.length > 0 && {
                        display: "grid",
                        gridTemplateColumns: itemSpans
                            .map((x) => `repeat(${x}, ${itemWidth}px)`)
                            .join(" 44px "),
                        columnGap: `${gap}px`,
                    },
                ]}
            >
                {renderListItem(item, !!isScrolling)}
            </Box>
        );
    },
    areEqual,
);

type FileThumbnailProps = {
    file: EnteFile;
    selected: boolean;
    isRangeSelectActive: boolean;
    selectOnClick: boolean;
    isInSelectRange: boolean;
    activeCollectionID: number;
    showPlaceholder: boolean;
    isFav: boolean;
    onClick: () => void;
    onSelect: (checked: boolean) => void;
    onHover: () => void;
    onRangeSelect: () => void;
    onContextMenu?: (event: React.MouseEvent) => void;
    style?: React.CSSProperties;
} & Pick<FileListProps, "user" | "emailByUserID" | "enableSelect">;

const FileThumbnail: React.FC<FileThumbnailProps> = ({
    file,
    user,
    enableSelect,
    selected,
    selectOnClick,
    isRangeSelectActive,
    isInSelectRange,
    isFav,
    emailByUserID,
    activeCollectionID,
    showPlaceholder,
    onClick,
    onSelect,
    onHover,
    onRangeSelect,
    onContextMenu,
    style,
}) => {
    const [imageURL, setImageURL] = useState<string | undefined>(undefined);
    const [isLongPressing, setIsLongPressing] = useState(false);

    const longPressHandlers = useMemo(
        () => ({
            onMouseDown: () => setIsLongPressing(true),
            onMouseUp: () => setIsLongPressing(false),
            onMouseLeave: () => setIsLongPressing(false),
            onTouchStart: () => setIsLongPressing(true),
            onTouchMove: () => setIsLongPressing(false),
            onTouchEnd: () => setIsLongPressing(false),
            onTouchCancel: () => setIsLongPressing(false),
        }),
        [],
    );

    useEffect(() => {
        const timerID = isLongPressing
            ? setTimeout(() => onSelect(!selected), 500)
            : undefined;
        return () => {
            if (timerID) clearTimeout(timerID);
        };
    }, [selected, onSelect, isLongPressing]);

    useEffect(() => {
        let didCancel = false;

        void downloadManager
            .renderableThumbnailURL(file, showPlaceholder)
            .then((url) => !didCancel && setImageURL(url))
            .catch((e: unknown) => {
                log.warn("Failed to fetch thumbnail", e);
            });

        return () => {
            didCancel = true;
        };
    }, [file, showPlaceholder]);

    const handleClick = () => {
        if (selectOnClick) {
            if (isRangeSelectActive) {
                onRangeSelect();
            } else {
                onSelect(!selected);
            }
        } else if (imageURL) {
            onClick();
        }
    };

    const handleSelect: React.ChangeEventHandler<HTMLInputElement> = (e) => {
        if (isRangeSelectActive) {
            onRangeSelect();
        } else {
            onSelect(e.target.checked);
        }
    };

    const handleHover = () => {
        if (isRangeSelectActive) {
            onHover();
        }
    };

    // Trash entries carry deleteBy despite the EnteFile type.
    const deleteBy =
        activeCollectionID == PseudoCollectionID.trash &&
        (file as EnteTrashFile).deleteBy;

    return (
        <FileThumbnail_
            key={`thumb-${file.id}}`}
            onClick={handleClick}
            onContextMenu={onContextMenu}
            onMouseEnter={handleHover}
            disabled={!imageURL}
            style={style}
            {...(enableSelect && longPressHandlers)}
        >
            {enableSelect && (
                <Check
                    type="checkbox"
                    checked={selected}
                    onChange={handleSelect}
                    $active={isRangeSelectActive && isInSelectRange}
                    onClick={(e) => e.stopPropagation()}
                />
            )}
            {file.metadata.hasStaticThumbnail ? (
                <StaticThumbnail fileType={file.metadata.fileType} />
            ) : imageURL ? (
                <img src={imageURL} />
            ) : (
                <LoadingThumbnail />
            )}
            {file.metadata.fileType == FileType.livePhoto ? (
                <FileTypeIndicatorOverlay>
                    <AlbumOutlinedIcon fontSize="small" />
                </FileTypeIndicatorOverlay>
            ) : (
                file.metadata.fileType == FileType.video && (
                    <VideoDurationOverlay duration={fileDurationString(file)} />
                )
            )}
            {selected && <SelectedOverlay />}
            {shouldShowAvatar(file, user) && (
                <AvatarOverlay>
                    <Avatar {...{ user, file, emailByUserID }} />
                </AvatarOverlay>
            )}
            {isFav && (
                <FavoriteOverlay>
                    <StarIcon fontSize="small" />
                </FavoriteOverlay>
            )}

            <HoverOverlay
                className="preview-card-hover-overlay"
                checked={selected}
            />
            {isRangeSelectActive && isInSelectRange && <InSelectRangeOverlay />}

            {deleteBy && (
                <TileBottomTextOverlay>
                    <Typography variant="small">
                        {formattedDateRelative(deleteBy)}
                    </Typography>
                </TileBottomTextOverlay>
            )}
        </FileThumbnail_>
    );
};

const FileThumbnail_ = styled("div")<{ disabled: boolean }>`
    display: flex;
    width: fit-content;
    margin-bottom: ${thumbnailGap}px;
    min-width: 100%;
    overflow: hidden;
    position: relative;
    flex: 1;
    cursor: ${(props) => (props.disabled ? "not-allowed" : "pointer")};
    user-select: none;
    & > img {
        object-fit: cover;
        max-width: 100%;
        min-height: 100%;
        flex: 1;
        pointer-events: none;
    }

    @media (pointer: fine) {
        &:hover {
            input[type="checkbox"] {
                visibility: visible;
                opacity: 0.5;
            }

            .preview-card-hover-overlay {
                opacity: 1;
            }
        }
    }

    border-radius: 4px;
`;

// Safari needs explicit display and positioning for these pseudo-elements.
const Check = styled("input")<{ $active: boolean }>(
    ({ theme, $active }) => `
    appearance: none;
    -webkit-appearance: none;
    -moz-appearance: none;
    position: absolute;
    z-index: 1;
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
        display: block;
        width: 19px;
        height: 19px;
        background-color: #ddd;
        border-radius: 50%;
        margin: 6px;
        transition: background-color 0.3s ease, opacity 0.3s ease;
        position: relative;
    }
    
    &::after {
        content: "";
        display: block;
        position: absolute;
        top: 50%;
        left: 50%;
        width: 5px;
        height: 11px;
        border: solid #333;
        border-width: 0 2px 2px 0;
        transform: translate(-50%, -60%) rotate(45deg);
        transition: border-color 0.3s ease, opacity 0.3s ease;
        transform-origin: center;
    }

    visibility: hidden;
    ${
        $active &&
        `
        visibility: visible;
        opacity: 0.5;
    `
    };
    
    &:hover {
        visibility: visible;
        opacity: 0.7;
    }
    
    &:checked {
        visibility: visible;
        opacity: 1 !important;
    }
    
    &:checked::before {
        background-color: ${theme.vars.palette.accent.main};
    }
    
    &:checked::after {
        border-color: #ddd;
    }
`,
);

const HoverOverlay = styled("div")<{ checked: boolean }>`
    opacity: 0;
    left: 0;
    top: 0;
    outline: none;
    height: 40%;
    width: 100%;
    position: absolute;
    ${(props) =>
        !props.checked &&
        "background:linear-gradient(rgba(0, 0, 0, 0.2), rgba(0, 0, 0, 0))"};
`;

const AvatarOverlay = styled(Overlay)`
    display: flex;
    justify-content: flex-end;
    align-items: flex-start;
    padding: 5px;
`;

const FavoriteOverlay = styled(Overlay)`
    display: flex;
    justify-content: flex-start;
    align-items: flex-end;
    padding: 5px;
    color: white;
    opacity: 0.6;
`;

const FileTypeIndicatorOverlay = styled(Overlay)`
    display: flex;
    justify-content: flex-end;
    align-items: flex-end;
    padding: 5px;
    color: white;
    background: linear-gradient(
        315deg,
        rgba(0 0 0 / 0.14) 0%,
        rgba(0 0 0 / 0.05) 30%,
        transparent 50%
    );
`;

const InSelectRangeOverlay = styled(Overlay)(
    ({ theme }) => `
    outline: none;
    background: ${theme.vars.palette.accent.main};
    opacity: 0.14;
`,
);

const SelectedOverlay = styled(Overlay)(
    ({ theme }) => `
    border: 2px solid ${theme.vars.palette.accent.main};
    border-radius: 4px;
`,
);

interface VideoDurationOverlayProps {
    duration: string | undefined;
}

const VideoDurationOverlay: React.FC<VideoDurationOverlayProps> = ({
    duration,
}) => (
    <FileTypeIndicatorOverlay>
        {duration ? (
            <Box sx={{ display: "flex", alignItems: "center" }}>
                <PlayArrowRoundedIcon
                    sx={{ fontSize: 14, display: "block", mr: 0.5 }}
                />
                <Typography variant="mini">{duration}</Typography>
            </Box>
        ) : (
            <PlayCircleOutlineOutlinedIcon fontSize="small" />
        )}
    </FileTypeIndicatorOverlay>
);

const shouldShowAvatar = (file: EnteFile, user: LocalUser | undefined) => {
    if (!user) return false;
    if (file.ownerID != user.id) return true;
    if (file.pubMagicMetadata?.data.uploaderName) return true;
    return false;
};
