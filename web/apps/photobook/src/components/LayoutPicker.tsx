import {
    getMirrorVariant,
    getVariantPreview,
    getVariantsForCount,
    type LayoutVariant,
} from "@/lib/layouts";
import { thumbnailShadow, uiColors } from "@/theme/colors";
import { Box } from "@mui/material";
import { useMemo } from "react";

const THUMB_W = 44;

interface PhotoThumbnail {
    url: string;
    rotation: number;
}

interface LayoutPickerProps {
    photoCount: number;
    currentVariant?: string;
    thumbnails: PhotoThumbnail[];
    onSelect: (variantKey: string) => void;
    isFrontCover?: boolean;
}

function VariantThumbnail({
    variant,
    isActive,
    thumbnails,
    onClick,
}: {
    variant: LayoutVariant;
    isActive: boolean;
    thumbnails: PhotoThumbnail[];
    onClick: () => void;
}) {
    const slots = useMemo(() => getVariantPreview(variant.key), [variant.key]);
    const isFullBleed = variant.key === "1-full";

    return (
        <Box
            onClick={(e) => {
                e.stopPropagation();
                onClick();
            }}
            sx={{
                width: THUMB_W,
                height: THUMB_W,
                bgcolor: uiColors.paper,
                borderRadius: 0.5,
                position: "relative",
                overflow: "hidden",
                cursor: "pointer",
                flexShrink: 0,
                boxShadow: thumbnailShadow,
                outline: isActive
                    ? "2px solid #08C225"
                    : "2px solid transparent",
                transition: "outline-color 0.15s",
                "&:hover": {
                    outline: isActive
                        ? "2px solid #08C225"
                        : `2px solid ${uiColors.muted}`,
                },
            }}
        >
            {slots.map((slot, i) => {
                const thumbnail = thumbnails[i];
                const rotation = thumbnail?.rotation ?? 0;
                const sideways = rotation % 180 !== 0;
                const GAP = isFullBleed ? 0 : 1.5;
                const left = (slot.x / 100) * THUMB_W + GAP;
                const top = (slot.y / 100) * THUMB_W + GAP;
                const width = (slot.width / 100) * THUMB_W - GAP * 2;
                const height = (slot.height / 100) * THUMB_W - GAP * 2;
                return (
                    <Box
                        key={i}
                        sx={{
                            position: "absolute",
                            left: `${left}px`,
                            top: `${top}px`,
                            width: `${width}px`,
                            height: `${height}px`,
                            bgcolor: thumbnail?.url ? undefined : "#b0b0b0",
                            borderRadius: isFullBleed ? 0 : "1px",
                            overflow: "hidden",
                        }}
                    >
                        {thumbnail?.url && (
                            <img
                                src={thumbnail.url}
                                alt=""
                                style={{
                                    position: "absolute",
                                    left: "50%",
                                    top: "50%",
                                    width: sideways ? height : width,
                                    height: sideways ? width : height,
                                    transform: `translate(-50%, -50%) rotate(${rotation}deg)`,
                                    objectFit: "cover",
                                    display: "block",
                                }}
                            />
                        )}
                    </Box>
                );
            })}
        </Box>
    );
}

export default function LayoutPicker({
    photoCount,
    currentVariant,
    thumbnails,
    onSelect,
    isFrontCover = false,
}: LayoutPickerProps) {
    const variants = useMemo(
        () =>
            getVariantsForCount(photoCount, isFrontCover).filter(
                (variant) => !isFrontCover || variant.key !== "1-moderate",
            ),
        [photoCount, isFrontCover],
    );

    if (variants.length === 0) return null;

    return (
        <Box
            sx={{
                display: "flex",
                flexDirection: "column",
                gap: 1,
                alignItems: "center",
            }}
        >
            {variants.map((v) => {
                const mirrorOfCurrent = currentVariant
                    ? getMirrorVariant(currentVariant)
                    : undefined;
                const isActive =
                    v.key === currentVariant || v.key === mirrorOfCurrent;
                return (
                    <VariantThumbnail
                        key={v.key}
                        variant={v}
                        isActive={isActive}
                        thumbnails={thumbnails}
                        onClick={() => {
                            if (isActive) {
                                const mirror = getMirrorVariant(
                                    currentVariant!,
                                );
                                if (mirror) onSelect(mirror);
                            } else {
                                onSelect(v.key);
                            }
                        }}
                    />
                );
            })}
        </Box>
    );
}
