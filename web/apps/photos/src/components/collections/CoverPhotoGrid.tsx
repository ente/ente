import { Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, styled } from "@mui/material";
import log from "ente-base/log";
import { downloadManager } from "ente-gallery/services/download";
import type { EnteFile } from "ente-media/file";
import {
    LoadingThumbnail,
    StaticThumbnail,
} from "ente-new/photos/components/PlaceholderThumbnails";
import { BaseTileButton } from "ente-new/photos/components/Tiles";
import { t } from "i18next";
import { memo, useEffect, useId, useState } from "react";
import { FixedSizeList, type ListChildComponentProps } from "react-window";

interface CoverPhotoGridProps {
    width: number;
    height: number;
    photos: EnteFile[];
    selectedFileID: number | undefined;
    currentCoverID: number | undefined;
    disabled: boolean;
    onSelect: (fileID: number) => void;
}

const tileSize = 148;
const gap = 10;
const padding = 24;

// A virtualized, single-selection grid without the gallery's interactions.
export const CoverPhotoGrid = ({
    width,
    height,
    ...selection
}: CoverPhotoGridProps) => {
    const availableWidth = Math.max(1, width - 2 * padding);
    const columns = Math.min(
        4,
        Math.max(1, Math.floor((availableWidth + gap) / (tileSize + gap))),
    );
    const size = Math.min(tileSize, availableWidth);

    return (
        <FixedSizeList
            width={width}
            height={height}
            itemCount={Math.ceil(selection.photos.length / columns)}
            itemSize={size + gap}
            itemData={{ ...selection, columns, size }}
            overscanCount={2}
            useIsScrolling
        >
            {CoverPhotoRow}
        </FixedSizeList>
    );
};

type RowData = Omit<CoverPhotoGridProps, "width" | "height"> & {
    columns: number;
    size: number;
};

const CoverPhotoRow = ({
    index,
    style,
    isScrolling,
    data,
}: ListChildComponentProps<RowData>) => {
    const {
        photos,
        columns,
        size,
        selectedFileID,
        currentCoverID,
        disabled,
        onSelect,
    } = data;
    return (
        <Box
            style={style}
            sx={{
                display: "flex",
                gap: `${gap}px`,
                px: `${padding}px`,
                boxSizing: "border-box",
            }}
        >
            {photos
                .slice(index * columns, (index + 1) * columns)
                .map((file) => (
                    <CoverPhotoCard
                        key={file.id}
                        file={file}
                        size={size}
                        isScrolling={Boolean(isScrolling)}
                        selected={file.id === selectedFileID}
                        current={file.id === currentCoverID}
                        disabled={disabled}
                        onSelect={onSelect}
                    />
                ))}
        </Box>
    );
};

interface CoverPhotoCardProps {
    file: EnteFile;
    size: number;
    isScrolling: boolean;
    selected: boolean;
    current: boolean;
    disabled: boolean;
    onSelect: (fileID: number) => void;
}

const CoverPhotoCard = memo(
    ({
        file,
        size,
        isScrolling,
        selected,
        current,
        disabled,
        onSelect,
    }: CoverPhotoCardProps) => {
        const currentLabelID = useId();
        // The row keys each card by file ID, so its thumbnail state cannot cross files.
        const [imageURL, setImageURL] = useState<string | null>();

        useEffect(() => {
            if (file.metadata.hasStaticThumbnail) return;
            let cancelled = false;
            void downloadManager
                .renderableThumbnailURL(file, isScrolling)
                .then((url) => {
                    if (!cancelled && url) {
                        setImageURL(url);
                    }
                })
                .catch((error: unknown) => {
                    if (!cancelled) {
                        setImageURL(null);
                        log.warn("Failed to fetch cover thumbnail", error);
                    }
                });
            return () => {
                cancelled = true;
            };
        }, [file, isScrolling]);

        return (
            <PhotoButton
                type="button"
                aria-label={file.metadata.title}
                aria-pressed={selected}
                aria-describedby={current ? currentLabelID : undefined}
                disabled={disabled}
                onClick={() => onSelect(file.id)}
                sx={{ width: size, height: size }}
            >
                {file.metadata.hasStaticThumbnail || imageURL === null ? (
                    <StaticThumbnail fileType={file.metadata.fileType} />
                ) : imageURL ? (
                    <img src={imageURL} alt="" />
                ) : (
                    <LoadingThumbnail />
                )}
                {selected && (
                    <Box
                        sx={{
                            position: "absolute",
                            inset: 0,
                            border: "3px solid #08c225",
                            borderRadius: "inherit",
                            pointerEvents: "none",
                        }}
                    >
                        <Box
                            sx={{
                                position: "absolute",
                                top: 7,
                                right: 7,
                                width: 26,
                                height: 26,
                                boxSizing: "border-box",
                                borderRadius: "50%",
                                bgcolor: "#08c225",
                                border: "2px solid #fff",
                                display: "grid",
                                placeItems: "center",
                            }}
                        >
                            <HugeiconsIcon
                                icon={Tick02Icon}
                                size={13}
                                strokeWidth={3}
                                color="#fff"
                                aria-hidden
                            />
                        </Box>
                    </Box>
                )}
                {current && (
                    <Box
                        id={currentLabelID}
                        sx={{
                            position: "absolute",
                            bottom: 10,
                            left: 10,
                            px: "11px",
                            py: "4px",
                            borderRadius: "10px",
                            bgcolor: "rgba(0 0 0 / 0.55)",
                            color: "#fff",
                            fontSize: 10,
                            fontWeight: 500,
                            lineHeight: "12px",
                            pointerEvents: "none",
                        }}
                    >
                        {t("current_cover")}
                    </Box>
                )}
            </PhotoButton>
        );
    },
);

const PhotoButton = styled(BaseTileButton)({
    flexShrink: 0,
    borderRadius: "12px",
    "& > div": { borderRadius: "inherit" },
    "&:focus-visible": {
        outline: "2px solid currentColor",
        outlineOffset: "-5px",
    },
    "&:disabled": { cursor: "default" },
});
