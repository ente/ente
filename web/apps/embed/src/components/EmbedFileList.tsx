import PlayCircleOutlineOutlinedIcon from "@mui/icons-material/PlayCircleOutlineOutlined";
import { Box, styled } from "@mui/material";
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
import React, { memo, useEffect, useMemo, useState } from "react";
import {
    FixedSizeList,
    areEqual,
    type ListChildComponentProps,
} from "react-window";

export interface EmbedFileListAnnotatedFile {
    file: EnteFile;
    timelineDateString: string;
}

export interface EmbedFileListProps {
    width: number;
    height: number;
    annotatedFiles: EmbedFileListAnnotatedFile[];
    onItemClick: (index: number) => void;
}

const THUMBNAIL_SIZE = 200;
const THUMBNAIL_GAP = 4;
const CONTAINER_PADDING = 4;

export const EmbedFileList: React.FC<EmbedFileListProps> = memo(
    ({ width, height, annotatedFiles, onItemClick }) => {
        const gridWidth = width - 2 * CONTAINER_PADDING;
        const gridHeight = height - 2 * CONTAINER_PADDING;

        return (
            <Container style={{ width, height }}>
                <EmbedVirtualGrid
                    height={gridHeight}
                    width={gridWidth}
                    annotatedFiles={annotatedFiles}
                    onItemClick={onItemClick}
                />
            </Container>
        );
    },
);

EmbedFileList.displayName = "EmbedFileList";

interface EmbedVirtualGridProps {
    width: number;
    height: number;
    annotatedFiles: EmbedFileListAnnotatedFile[];
    onItemClick: (index: number) => void;
}

const EmbedVirtualGrid: React.FC<EmbedVirtualGridProps> = memo(
    ({ width, height, annotatedFiles, onItemClick }) => {
        const columnCount = Math.max(
            1,
            Math.floor(
                (width + THUMBNAIL_GAP) / (THUMBNAIL_SIZE + THUMBNAIL_GAP),
            ),
        );
        const size = (width - (columnCount - 1) * THUMBNAIL_GAP) / columnCount;
        const rowCount = Math.ceil(annotatedFiles.length / columnCount);
        const itemData = useMemo(
            () => ({ annotatedFiles, columnCount, onItemClick, size }),
            [annotatedFiles, columnCount, onItemClick, size],
        );

        return (
            <FixedSizeList
                height={height}
                itemData={itemData}
                itemCount={rowCount}
                itemSize={size + THUMBNAIL_GAP}
                overscanCount={2}
                width={width}
            >
                {EmbedFileRow}
            </FixedSizeList>
        );
    },
);

EmbedVirtualGrid.displayName = "EmbedVirtualGrid";

interface EmbedFileCellData {
    annotatedFiles: EmbedFileListAnnotatedFile[];
    columnCount: number;
    onItemClick: (index: number) => void;
    size: number;
}

const EmbedFileRow = memo(
    ({
        index: rowIndex,
        style,
        data,
    }: ListChildComponentProps<EmbedFileCellData>) => {
        const startIndex = rowIndex * data.columnCount;
        const rowFiles = data.annotatedFiles.slice(
            startIndex,
            startIndex + data.columnCount,
        );

        return (
            <div style={style}>
                <GridRow columns={data.columnCount} gap={THUMBNAIL_GAP}>
                    {rowFiles.map((annotatedFile, columnIndex) => {
                        const fileIndex = startIndex + columnIndex;
                        return (
                            <EmbedFileTile
                                key={annotatedFile.file.id}
                                file={annotatedFile.file}
                                size={data.size}
                                onClick={() => data.onItemClick(fileIndex)}
                            />
                        );
                    })}
                </GridRow>
            </div>
        );
    },
    areEqual,
);

EmbedFileRow.displayName = "EmbedFileRow";

interface EmbedFileTileProps {
    file: EnteFile;
    size: number;
    onClick: () => void;
}

const EmbedFileTile: React.FC<EmbedFileTileProps> = memo(
    ({ file, size, onClick }) => {
        const [thumbnailSrc, setThumbnailSrc] = useState<string>();
        const [isLoading, setIsLoading] = useState(true);

        const isVideoFile = useMemo(
            () => file.metadata.fileType === FileType.video,
            [file.metadata.fileType],
        );

        useEffect(() => {
            let didCancel = false;

            setIsLoading(true);
            setThumbnailSrc(undefined);
            void downloadManager
                .renderableThumbnailURL(file)
                .then((url) => !didCancel && setThumbnailSrc(url))
                .catch((e: unknown) => {
                    log.warn("Failed to fetch embed thumbnail", e);
                })
                .finally(() => {
                    if (!didCancel) setIsLoading(false);
                });

            return () => {
                didCancel = true;
            };
        }, [file]);

        const content = useMemo(() => {
            if (isLoading) {
                return <LoadingThumbnail />;
            }

            if (!thumbnailSrc) {
                return <StaticThumbnail fileType={file.metadata.fileType} />;
            }

            return (
                <ThumbnailImage
                    src={thumbnailSrc}
                    alt=""
                    style={{ width: size, height: size }}
                />
            );
        }, [isLoading, thumbnailSrc, size, file.metadata.fileType]);

        return (
            <TileContainer
                style={{ width: size, height: size }}
                onClick={onClick}
            >
                {content}
                {isVideoFile && (
                    <VideoOverlay>
                        <PlayCircleOutlineOutlinedIcon />
                        <TileBottomTextOverlay>
                            {fileDurationString(file)}
                        </TileBottomTextOverlay>
                    </VideoOverlay>
                )}
            </TileContainer>
        );
    },
);

EmbedFileTile.displayName = "EmbedFileTile";

const Container = styled("div")({
    boxSizing: "border-box",
    overflow: "hidden",
    padding: `${CONTAINER_PADDING}px`,
});

const GridRow = styled("div")<{ columns: number; gap: number }>(
    ({ columns, gap }) => ({
        display: "grid",
        gap: `${gap}px`,
        gridTemplateColumns: `repeat(${columns}, 1fr)`,
    }),
);

const TileContainer = styled("div")({
    position: "relative",
    cursor: "pointer",
    borderRadius: "4px",
    overflow: "hidden",
    transition: "transform 0.2s ease",
    "&:hover": { transform: "scale(1.02)" },
});

const ThumbnailImage = styled("img")({
    objectFit: "cover",
    borderRadius: "4px",
});

const VideoOverlay = styled(Box)({
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    color: "white",
    "& svg": {
        fontSize: "2rem",
        filter: "drop-shadow(0 1px 3px rgba(0,0,0,0.5))",
    },
});
