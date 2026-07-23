import { AddPhotosIcon } from "@/public-album/components/ActionIcons";
import { thumbnailManager } from "@/public-album/media/thumbnails/thumbnail-manager";
import type { SelectedState } from "@/public-album/utils/file";
import {
    handleSelectCreator,
    handleSelectCreatorMulti,
} from "@/public-album/utils/photo-frame";
import AlbumOutlinedIcon from "@mui/icons-material/AlbumOutlined";
import PlayArrowRoundedIcon from "@mui/icons-material/PlayArrowRounded";
import PlayCircleOutlineOutlinedIcon from "@mui/icons-material/PlayCircleOutlineOutlined";
import { Box, Button, Checkbox, Typography, styled } from "@mui/material";
import { Overlay } from "ente-base/components/containers";
import log from "ente-base/log";
import type { EnteFile } from "ente-media/file";
import { fileDurationString } from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import {
    LoadingThumbnail,
    StaticThumbnail,
} from "ente-new/photos/components/PlaceholderThumbnails";
import {
    computeThumbnailGridLayoutParams,
    thumbnailGap,
    type ThumbnailGridLayoutParams,
} from "ente-new/photos/components/utils/thumbnail-grid-layout";
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

/**
 * A component with an explicit height suitable for being plugged in as the
 * {@link header} or {@link footer} of the {@link FileList}.
 */
export interface FileListHeaderOrFooter {
    /**
     * The component itself.
     */
    component: React.ReactNode;
    /**
     * The height of the component (in px).
     */
    height: number;
    /**
     * By default, all items in the {@link FileList}, including headers and
     * footers injected using this type, get an inline margin.
     *
     * Set this property to `true` to omit this default margin, and instead
     * have the component extend to the container's edges.
     */
    extendToInlineEdges?: boolean;
}

/**
 * Data needed to render each row in the variable size list that comprises the
 * file list.
 */
type FileListItem =
    | {
          type: "file";
          /**
           * The height of the row that will render this item.
           */
          height: number;
          /**
           * Groups of items that are shown in the row.
           *
           * Each group spans multiple columns (the number of columns being given by
           * the length of {@link annotatedFiles} or the {@link span}). Groups are
           * separated by gaps.
           */
          groups: {
              /**
               * The annotated files in this group.
               */
              annotatedFiles: FileListAnnotatedFile[];
              /**
               * The index of the first annotated file in the component's global list
               * of annotated files.
               */
              annotatedFilesStartIndex: number;
          }[];
      }
    | {
          type: "date";
          height: number;
          groups: {
              /**
               * The date string to show.
               */
              date: string;
              /**
               * The number of columns to span.
               */
              dateSpan: number;
          }[];
      }
    | {
          type: "span";
          height: number;
          /**
           * The React component that is the rendered representation of the item.
           */
          component: React.ReactNode;
          extendToInlineEdges?: boolean;
      };

export interface FileListAnnotatedFile {
    file: EnteFile;
    /**
     * The date string using with the associated {@link file} should be shown in
     * the timeline.
     *
     * [Note: Timeline date string]
     *
     * The timeline date string is a formatted date string under which a
     * particular file should be grouped in the gallery listing. e.g. "Today",
     * "Yesterday", "Fri, 21 Feb" etc.
     *
     * All files which have the same timelineDateString will be grouped under a
     * single section in the gallery listing, prefixed by the timelineDateString
     * itself, and a checkbox to select all files on that date.
     */
    timelineDateString: string;
}

interface MasonryLayoutItem {
    file: EnteFile;
    fileIndex: number;
    left: number;
    top: number;
    bottom: number;
    width: number;
    height: number;
}

interface MasonryLayout {
    items: MasonryLayoutItem[];
    rows: MasonryLayoutItem[][];
    totalHeight: number;
}

interface MasonrySourceItem {
    file: EnteFile;
    fileIndex: number;
    aspectRatio: number;
}

export interface FileListProps {
    /** The height we should occupy (needed since the list is virtualized). */
    height: number;
    /** The width we should occupy.*/
    width: number;
    /**
     * The files to show, annotated with cached precomputed properties that are
     * frequently needed by the {@link FileList}.
     */
    annotatedFiles: FileListAnnotatedFile[];
    /**
     * The visual layout used to render the file listing.
     */
    layout?: "grid" | "masonry";
    /**
     * An optional component shown before all the items in the list.
     *
     * It is not sticky, and scrolls along with the content of the list.
     */
    header?: FileListHeaderOrFooter;
    /**
     * An optional component shown after all the items in the list.
     *
     * It is not sticky, and scrolls along with the content of the list.
     */
    footer?: FileListHeaderOrFooter;
    /**
     * If `true`, then the user can select files in the listing by clicking on
     * their thumbnails (and other range selection mechanisms).
     */
    enableSelect?: boolean;
    setSelected: (
        selected: SelectedState | ((selected: SelectedState) => SelectedState),
    ) => void;
    selected: SelectedState;
    /** A stable key used to reset the virtualized list when the file set changes. */
    activeCollectionID: number;
    /** Optional action shown below the empty list message. */
    emptyStateAction?: { label: string; onClick: () => void };
    /**
     * Called when the user activates the thumbnail at the given {@link index}.
     *
     * This corresponding file would be at the corresponding index of
     * {@link annotatedFiles}.
     */
    onItemClick: (index: number) => void;
}

/**
 * A virtualized list of files, each represented by their thumbnail.
 */
export const FileList: React.FC<FileListProps> = ({
    height,
    width,
    layout = "grid",
    header,
    footer,
    annotatedFiles,
    enableSelect,
    selected,
    setSelected,
    activeCollectionID,
    emptyStateAction,
    onItemClick,
}) => {
    const [_items, setItems] = useState<FileListItem[]>([]);
    const items = useDeferredValue(_items);

    const [rangeStartIndex, setRangeStartIndex] = useState<number | undefined>(
        undefined,
    );
    const [hoverIndex, setHoverIndex] = useState<number | undefined>(undefined);
    const [isShiftKeyPressed, setIsShiftKeyPressed] = useState(false);
    const [masonryScrollTop, setMasonryScrollTop] = useState(0);
    const [masonryIsScrolling, setMasonryIsScrolling] = useState(false);
    const masonryScrollIdleTimeoutRef = useRef<
        ReturnType<typeof setTimeout> | undefined
    >(undefined);
    // Timeline date strings for which all photos have been selected.
    //
    // See: [Note: Timeline date string]
    const [checkedTimelineDateStrings, setCheckedTimelineDateStrings] =
        useState(new Set<string>());
    const listRef = useRef<VariableSizeList | null>(null);
    const outerRef = useRef<HTMLDivElement | null>(null);

    const layoutParams = useMemo(
        () => computeThumbnailGridLayoutParams(width),
        [width],
    );
    const shouldUseMasonry = layout === "masonry";

    useEffect(() => {
        if (shouldUseMasonry) {
            setItems([]);
            return;
        }

        // Since width and height are dependencies, there might be too many
        // updates to the list during a resize. The list computation too, while
        // fast, is non-trivial.
        //
        // To avoid these issues, the we use `useDeferredValue`: if it gets
        // another update when processing one, React will restart the background
        // rerender from scratch.

        let items: FileListItem[] = [];

        if (header) items.push(asFullSpanFileListItem(header));

        const { isSmallerLayout, columns } = layoutParams;
        const fileItemHeight = layoutParams.itemHeight + layoutParams.gap;
        // A running counter of files that have been pushed into items, and
        // a function to push them (incrementing the counter).
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
                // If we get here, the combined number of files across
                // splits is less than the number of columns.
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
                // A single group of files, but the number of such files
                // might be more than what fits a single row.
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

            // Check if the files in this split can be added to same row.
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

        if (!annotatedFiles.length) {
            items.push({
                height: emptyStateHeightForViewport(height, header, footer),
                type: "span",
                component: (
                    <FileListEmptyState emptyStateAction={emptyStateAction} />
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
        shouldUseMasonry,
        layoutParams,
        emptyStateAction,
    ]);

    useEffect(() => {
        // Refresh list
        listRef.current?.resetAfterIndex(0);
    }, [items]);

    useEffect(() => {
        const notSelectedFiles = annotatedFiles.filter(
            (af) => !selected[af.file.id],
        );

        // Get dates of files which were manually unselected.
        const unselectedDates = new Set(
            notSelectedFiles.map((af) => af.timelineDateString),
        );

        // Get files which were manually selected.
        const localSelectedFiles = annotatedFiles.filter(
            (af) => !unselectedDates.has(af.timelineDateString),
        );

        // Get dates of files which were manually selected.
        const localSelectedDates = new Set(
            localSelectedFiles.map((af) => af.timelineDateString),
        );

        setCheckedTimelineDateStrings((prev) => {
            const checked = new Set(prev);
            // Uncheck the "Select all" checkbox if any of the files on the date
            // is unselected.
            unselectedDates.forEach((date) => checked.delete(date));
            // Check the "Select all" checkbox if all of the files on a date are
            // selected.
            localSelectedDates.forEach((date) => checked.add(date));
            return checked;
        });
    }, [annotatedFiles, selected]);

    const handleSelectMulti = useMemo(
        () => handleSelectCreatorMulti(setSelected),
        [setSelected],
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

            // All files on a checked/unchecked day.
            const filesOnADay = annotatedFiles.filter(
                (af) => af.timelineDateString === date,
            );

            handleSelectMulti(filesOnADay.map((af) => af.file))(isDateSelected);
        },
        [annotatedFiles, checkedTimelineDateStrings, handleSelectMulti],
    );

    const handleSelect = useMemo(
        () => handleSelectCreator(setSelected, setRangeStartIndex),
        [setSelected],
    );

    const isFileSelected = useCallback(
        (file: EnteFile) => !!selected[file.id],
        [selected],
    );

    const haveSelection = selected.count > 0;

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

    const renderListItem = useCallback(
        (item: FileListItem, isScrolling: boolean) => {
            const haveSelection = !!enableSelect && selected.count > 0;
            switch (item.type) {
                case "date":
                    return intersperseWithGaps(
                        item.groups,
                        ({ date, dateSpan }) => [
                            <DateListItem key={date} span={dateSpan}>
                                {haveSelection && (
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
                                        enableSelect={!!enableSelect}
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
                                        showPlaceholder={isScrolling}
                                        onClick={() => onItemClick(index)}
                                        onSelect={handleSelect(file, index)}
                                        onHover={() => setHoverIndex(index)}
                                        onRangeSelect={() =>
                                            handleRangeSelect(index)
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
            checkedTimelineDateStrings,
            handleRangeSelect,
            handleSelect,
            hoverIndex,
            isShiftKeyPressed,
            isFileSelected,
            onChangeSelectAllCheckBox,
            onItemClick,
            rangeStartIndex,
            enableSelect,
            selected,
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

    const masonryTargetRowHeight = useMemo(
        () => preferredMasonryRowHeight(layoutParams.containerWidth),
        [layoutParams.containerWidth],
    );
    const masonryInnerWidth = useMemo(
        () => Math.max(0, width - 2 * layoutParams.paddingInline),
        [layoutParams.paddingInline, width],
    );
    const masonryLayout = useMemo<MasonryLayout>(() => {
        if (
            !shouldUseMasonry ||
            masonryTargetRowHeight <= 0 ||
            masonryInnerWidth <= 0 ||
            !annotatedFiles.length
        ) {
            return { items: [], rows: [], totalHeight: 0 };
        }

        const rows = new Array<MasonryLayoutItem[]>();
        const items: MasonryLayoutItem[] = [];
        const masonrySourceItems = new Array<MasonrySourceItem>();
        let rowTop = 0;
        let currentRow = new Array<MasonrySourceItem>();
        let currentRowAspectRatio = 0;
        const useAdaptiveMobileRows = shouldUseAdaptiveMobileMasonryRows(
            layoutParams.containerWidth,
        );

        const placeCurrentRow = (fitToWidth: boolean) => {
            if (!currentRow.length || currentRowAspectRatio <= 0) return;
            const totalGapWidth = (currentRow.length - 1) * layoutParams.gap;
            const maxContentWidth = Math.max(
                1,
                masonryInnerWidth - totalGapWidth,
            );
            const naturalRowHeight = Math.max(
                1,
                maxContentWidth / currentRowAspectRatio,
            );
            const rowHeight = fitToWidth
                ? naturalRowHeight
                : Math.min(masonryTargetRowHeight, naturalRowHeight);
            const row = new Array<MasonryLayoutItem>();
            let left = 0;

            for (const { file, fileIndex, aspectRatio } of currentRow) {
                const itemWidth = Math.max(1, rowHeight * aspectRatio);
                const item = {
                    file,
                    fileIndex,
                    top: rowTop,
                    bottom: rowTop + rowHeight,
                    left,
                    width: itemWidth,
                    height: rowHeight,
                } satisfies MasonryLayoutItem;
                items.push(item);
                row.push(item);
                left += itemWidth + layoutParams.gap;
            }

            rows.push(row);
            rowTop += rowHeight + layoutParams.gap;
            currentRow = [];
            currentRowAspectRatio = 0;
        };

        for (const [fileIndex, { file }] of annotatedFiles.entries()) {
            const dimensions = fileMasonryDimensions(file);
            const aspectRatio = Math.max(
                0.1,
                dimensions.width / dimensions.height,
            );
            masonrySourceItems.push({ file, fileIndex, aspectRatio });
        }

        if (useAdaptiveMobileRows) {
            let sourceIndex = 0;
            let rowIndex = 0;
            while (sourceIndex < masonrySourceItems.length) {
                const desiredCount = preferredMobileMasonryRowItemCount(
                    masonrySourceItems,
                    sourceIndex,
                    rowIndex,
                );
                const boundedCount = Math.max(
                    1,
                    Math.min(
                        desiredCount,
                        masonrySourceItems.length - sourceIndex,
                    ),
                );
                for (let i = 0; i < boundedCount; i += 1) {
                    const sourceItem = masonrySourceItems[sourceIndex + i]!;
                    currentRow.push(sourceItem);
                    currentRowAspectRatio += sourceItem.aspectRatio;
                }
                placeCurrentRow(true);
                sourceIndex += boundedCount;
                rowIndex += 1;
            }
        } else {
            for (const sourceItem of masonrySourceItems) {
                currentRow.push(sourceItem);
                currentRowAspectRatio += sourceItem.aspectRatio;

                const rowWidthAtTargetHeight =
                    currentRowAspectRatio * masonryTargetRowHeight +
                    (currentRow.length - 1) * layoutParams.gap;
                if (rowWidthAtTargetHeight >= masonryInnerWidth) {
                    placeCurrentRow(true);
                }
            }
            placeCurrentRow(false);
        }

        const totalHeight = Math.max(0, rowTop - layoutParams.gap);
        return { items, rows, totalHeight };
    }, [
        annotatedFiles,
        masonryInnerWidth,
        layoutParams.containerWidth,
        layoutParams.gap,
        masonryTargetRowHeight,
        shouldUseMasonry,
    ]);
    const masonryHeaderHeight = header?.height ?? 0;
    const masonryViewportTop = Math.max(
        0,
        masonryScrollTop - masonryHeaderHeight,
    );
    const masonryViewportBottom = masonryViewportTop + height;
    const masonryOverscan = Math.max(height, 800);
    const masonryVisibleItems = useMemo(() => {
        const minTop = masonryViewportTop - masonryOverscan;
        const maxTop = masonryViewportBottom + masonryOverscan;
        const visible = new Array<MasonryLayoutItem>();
        const startRowIndex = firstVisibleMasonryRowIndex(
            masonryLayout.rows,
            minTop,
        );

        for (
            let rowIndex = startRowIndex;
            rowIndex < masonryLayout.rows.length;
            rowIndex += 1
        ) {
            const row = masonryLayout.rows[rowIndex]!;
            if (!row.length) continue;
            if (row[0]!.top > maxTop) break;
            const startIndex = firstVisibleIndexForMasonryTrack(row, minTop);
            for (let i = startIndex; i < row.length; i += 1) {
                const item = row[i]!;
                if (item.top > maxTop) break;
                visible.push(item);
            }
        }

        return visible;
    }, [
        masonryLayout.rows,
        masonryOverscan,
        masonryViewportBottom,
        masonryViewportTop,
    ]);

    const handleMasonryScroll: React.UIEventHandler<HTMLDivElement> =
        useCallback((event) => {
            const scrollOffset = event.currentTarget.scrollTop;
            setMasonryScrollTop(scrollOffset);
            setMasonryIsScrolling(true);
            if (masonryScrollIdleTimeoutRef.current) {
                clearTimeout(masonryScrollIdleTimeoutRef.current);
            }
            masonryScrollIdleTimeoutRef.current = setTimeout(() => {
                setMasonryIsScrolling(false);
                masonryScrollIdleTimeoutRef.current = undefined;
            }, masonryScrollIdleMs);
        }, []);

    useEffect(
        () => () => {
            if (masonryScrollIdleTimeoutRef.current) {
                clearTimeout(masonryScrollIdleTimeoutRef.current);
            }
        },
        [],
    );

    useEffect(() => {
        if (!shouldUseMasonry) {
            setMasonryScrollTop(0);
            setMasonryIsScrolling(false);
            if (masonryScrollIdleTimeoutRef.current) {
                clearTimeout(masonryScrollIdleTimeoutRef.current);
                masonryScrollIdleTimeoutRef.current = undefined;
            }
        }
    }, [shouldUseMasonry]);

    const renderMasonryItem = useCallback(
        ({
            file,
            fileIndex,
            top,
            left,
            width,
            height,
            bottom,
        }: MasonryLayoutItem) => {
            const isInViewport =
                bottom > masonryViewportTop && top < masonryViewportBottom;
            return (
                <Box
                    key={`masonry-photo-${file.id}-${fileIndex}`}
                    sx={{ position: "absolute", top, left, width, height }}
                >
                    <FileThumbnail
                        key={`tile-${file.id}-selected-${selected[file.id] ?? false}`}
                        enableSelect={!!enableSelect}
                        file={file}
                        selected={isFileSelected(file)}
                        selectOnClick={haveSelection}
                        isRangeSelectActive={isShiftKeyPressed && haveSelection}
                        isInSelectRange={
                            rangeStartIndex !== undefined &&
                            hoverIndex !== undefined &&
                            ((fileIndex >= rangeStartIndex &&
                                fileIndex <= hoverIndex) ||
                                (fileIndex >= hoverIndex &&
                                    fileIndex <= rangeStartIndex))
                        }
                        showPlaceholder={masonryIsScrolling && !isInViewport}
                        onClick={() => onItemClick(fileIndex)}
                        onSelect={handleSelect(file, fileIndex)}
                        onHover={() => setHoverIndex(fileIndex)}
                        onRangeSelect={() => handleRangeSelect(fileIndex)}
                        isMasonry
                        style={{ width: "100%", height: "100%" }}
                    />
                </Box>
            );
        },
        [
            enableSelect,
            handleRangeSelect,
            handleSelect,
            haveSelection,
            hoverIndex,
            isFileSelected,
            isShiftKeyPressed,
            masonryIsScrolling,
            masonryViewportBottom,
            masonryViewportTop,
            onItemClick,
            rangeStartIndex,
            selected,
        ],
    );

    if (shouldUseMasonry) {
        return (
            <Box sx={{ position: "relative", width, height }}>
                <Box
                    ref={outerRef}
                    sx={{ width: "100%", height: "100%", overflowY: "auto" }}
                    onScroll={handleMasonryScroll}
                >
                    {header && (
                        <Box
                            sx={{
                                px: header.extendToInlineEdges
                                    ? 0
                                    : `${layoutParams.paddingInline}px`,
                            }}
                        >
                            {header.component}
                        </Box>
                    )}
                    {masonryLayout.items.length > 0 ? (
                        <Box sx={{ px: `${layoutParams.paddingInline}px` }}>
                            <Box
                                sx={{
                                    width: masonryInnerWidth,
                                    position: "relative",
                                    height: masonryLayout.totalHeight,
                                }}
                            >
                                {masonryVisibleItems.map(renderMasonryItem)}
                            </Box>
                        </Box>
                    ) : (
                        <FileListEmptyState
                            emptyStateAction={emptyStateAction}
                            sx={{
                                minHeight: `${emptyStateHeightForViewport(
                                    height,
                                    header,
                                    footer,
                                )}px`,
                            }}
                        />
                    )}
                    {footer && (
                        <Box
                            sx={{
                                px: footer.extendToInlineEdges
                                    ? 0
                                    : `${layoutParams.paddingInline}px`,
                            }}
                        >
                            {footer.component}
                        </Box>
                    )}
                </Box>
            </Box>
        );
    }

    if (!items.length) {
        return <></>;
    }

    return (
        <Box sx={{ position: "relative", width, height }}>
            <VariableSizeList
                key={activeCollectionID}
                ref={listRef}
                outerRef={outerRef}
                {...{ width, height, itemData, itemSize, itemKey }}
                itemCount={items.length}
                overscanCount={3}
                useIsScrolling
            >
                {FileListRow}
            </VariableSizeList>
        </Box>
    );
};

/**
 * Return a new array of splits, each split containing {@link annotatedFiles}
 * which have the same {@link timelineDateString}.
 */
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

const firstVisibleIndexForMasonryTrack = (
    track: MasonryLayoutItem[],
    minTop: number,
) => {
    let low = 0;
    let high = track.length;
    while (low < high) {
        const mid = Math.floor((low + high) / 2);
        if (track[mid]!.bottom < minTop) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return low;
};

const firstVisibleMasonryRowIndex = (
    rows: MasonryLayoutItem[][],
    minTop: number,
) => {
    let low = 0;
    let high = rows.length;
    while (low < high) {
        const mid = Math.floor((low + high) / 2);
        const row = rows[mid]!;
        const rowBottom = row.length ? row[row.length - 1]!.bottom : -Infinity;
        if (rowBottom < minTop) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return low;
};

const fileMasonryDimensions = (file: EnteFile) => {
    if (shouldUseSquareMasonryDimensions(file)) {
        return { width: 1, height: 1 };
    }

    const width = file.pubMagicMetadata?.data.w;
    const height = file.pubMagicMetadata?.data.h;
    if (width && height && width > 0 && height > 0) {
        return { width, height };
    }

    return { width: 1, height: 1 };
};

const shouldUseSquareMasonryDimensions = (file: EnteFile) =>
    file.metadata.fileType === FileType.video ||
    file.metadata.fileType === FileType.livePhoto;

const masonryScrollIdleMs = 120;

const preferredMasonryRowHeight = (containerWidth: number) => {
    if (containerWidth < 560) return 210;
    if (containerWidth < 900) return 250;
    if (containerWidth < 1280) return 300;
    if (containerWidth < 1800) return 345;
    return 385;
};

const shouldUseAdaptiveMobileMasonryRows = (containerWidth: number) =>
    containerWidth < 560;

const preferredMobileMasonryRowItemCount = (
    sourceItems: MasonrySourceItem[],
    startIndex: number,
    rowIndex: number,
) => {
    const first = sourceItems[startIndex];
    const second = sourceItems[startIndex + 1];
    const third = sourceItems[startIndex + 2];
    if (!first || !second) return 1;

    const firstRatio = first.aspectRatio;
    const secondRatio = second.aspectRatio;
    if (firstRatio >= 1.25) return 1;

    const firstIsPortrait = firstRatio < 0.9;
    const secondIsPortrait = secondRatio < 0.9;
    const thirdIsPortrait = !!third && third.aspectRatio < 0.9;

    // Occasionally show one tall portrait in a row to mimic the mobile collage feel.
    if (firstRatio <= 0.62 && rowIndex % 4 === 1) return 1;

    if (firstIsPortrait && secondIsPortrait && third && thirdIsPortrait) {
        return rowIndex % 3 === 0 ? 3 : 2;
    }
    if (firstIsPortrait && secondIsPortrait) return 2;

    if (firstRatio + secondRatio >= 1.6) return 2;
    if (third && firstRatio + secondRatio + third.aspectRatio >= 1.9) return 3;
    return 2;
};

/**
 * For each element of {@link xs}, obtain an array by applying {@link f},
 * then obtain a gap element by applying {@link g}. Return a flattened array
 * containing all of these, except the trailing gap.
 */
const intersperseWithGaps = <T, U>(
    xs: T[],
    f: (x: T) => U[],
    g: (x: T) => U,
) => {
    const ys = xs.map((x) => [...f(x), g(x)]).flat();
    return ys.slice(0, ys.length - 1);
};

/**
 * A list item container that spans the full width.
 */
const FullSpanListItem = styled("div")`
    display: flex;
    align-items: center;
`;

const NoFilesListItem = styled(FullSpanListItem)`
    min-height: 100%;
    flex-direction: column;
    gap: 8px;
    justify-content: center;
`;

const minEmptyStateHeight = 96;

const emptyStateHeightForViewport = (
    height: number,
    header?: FileListHeaderOrFooter,
    footer?: FileListHeaderOrFooter,
) =>
    Math.max(
        minEmptyStateHeight,
        height - (header?.height ?? 0) - (footer?.height ?? 0),
    );

interface FileListEmptyStateProps {
    emptyStateAction?: FileListProps["emptyStateAction"];
    sx?: React.ComponentProps<typeof Box>["sx"];
}

const FileListEmptyState: React.FC<FileListEmptyStateProps> = ({
    emptyStateAction,
    sx,
}) => (
    <NoFilesListItem sx={sx}>
        {emptyStateAction ? (
            <EmptyStateActionButton
                type="button"
                onClick={emptyStateAction.onClick}
                startIcon={<AddPhotosIcon size={20} />}
            >
                {emptyStateAction.label}
            </EmptyStateActionButton>
        ) : (
            <Typography sx={{ color: "text.faint" }}>
                {t("nothing_here")}
            </Typography>
        )}
    </NoFilesListItem>
);

const EmptyStateActionButton = styled(Button)(({ theme }) => ({
    borderRadius: "16px",
    paddingBlock: "11px",
    paddingInline: "14px",
    backgroundColor: theme.vars.palette.secondary.main,
    color: theme.vars.palette.text.base,
    fontWeight: 600,
    "&:hover": { backgroundColor: theme.vars.palette.secondary.dark },
    "& .MuiButton-startIcon": { marginInlineStart: 0 },
    "& svg": { color: "inherit" },
}));

/**
 * Convert a {@link FileListHeaderOrFooter} into a {@link FileListItem}
 * that spans the entire width available to the row.
 */
const asFullSpanFileListItem = ({
    component,
    ...rest
}: FileListHeaderOrFooter): FileListItem => ({
    ...rest,
    type: "span",
    component: <FullSpanListItem>{component}</FullSpanListItem>,
});

/**
 * An grid item, spanning {@link span} columns.
 */
const GridSpanListItem = styled("div")<{ span: number }>`
    grid-column: span ${({ span }) => span};
    display: flex;
    align-items: center;
`;

/**
 * The fixed height (in px) of {@link DateListItem}.
 */
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
    showPlaceholder: boolean;
    onClick: () => void;
    onSelect: (checked: boolean) => void;
    onHover: () => void;
    onRangeSelect: () => void;
    isMasonry?: boolean;
    style?: React.CSSProperties;
} & Pick<FileListProps, "enableSelect">;

const FileThumbnail: React.FC<FileThumbnailProps> = ({
    file,
    enableSelect,
    selected,
    selectOnClick,
    isRangeSelectActive,
    isInSelectRange,
    showPlaceholder,
    onClick,
    onSelect,
    onHover,
    onRangeSelect,
    isMasonry,
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

        void thumbnailManager
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

    return (
        <FileThumbnail_
            key={`thumb-${file.id}}`}
            onClick={handleClick}
            onMouseEnter={handleHover}
            disabled={!imageURL}
            $disableBottomMargin={!!isMasonry}
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

            <HoverOverlay
                className="preview-card-hover-overlay"
                checked={selected}
            />
            {isRangeSelectActive && isInSelectRange && <InSelectRangeOverlay />}
        </FileThumbnail_>
    );
};

const FileThumbnail_ = styled("div")<{
    disabled: boolean;
    $disableBottomMargin: boolean;
}>`
    display: flex;
    width: fit-content;
    margin-bottom: ${({ $disableBottomMargin }) =>
        $disableBottomMargin ? "0px" : `${thumbnailGap}px`};
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
        display: block; /* Critical for Safari */
        width: 19px;
        height: 19px;
        background-color: #ddd;
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
        border: solid #333;
        border-width: 0 2px 2px 0;
        transform: translate(-50%, -60%) rotate(45deg);
        transition: border-color 0.3s ease, opacity 0.3s ease;
        transform-origin: center;
    }

    /* Default state - hide both */
    visibility: hidden;
    
    /* When $active - show both with reduced opacity */
    ${
        $active &&
        `
        visibility: visible;
        opacity: 0.5;
    `
    };
    
    /* Hover state - show both */
    &:hover {
        visibility: visible;
        opacity: 0.7;
    }
    
    /* Checked state - show both with full opacity and colored */
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

/**
 * An overlay with a gradient, showing the file type indicator (e.g. live photo,
 * video) at the bottom right.
 */
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
