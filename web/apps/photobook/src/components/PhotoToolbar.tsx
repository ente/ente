import { useBook } from "@/context/book";
import type { PhotoSlot } from "@/lib/types";
import { accentGreen } from "@/theme/buttons";
import { pageMenuColors, popupShadow, toolbarColors } from "@/theme/colors";
import { Box, IconButton, Tooltip } from "@mui/material";
import { useState } from "react";
import {
    DeleteIcon,
    PanIcon,
    RotatePhotoIcon,
    ZoomInIcon,
    ZoomOutIcon,
} from "./icons";

export default function PhotoToolbar({
    pageId,
    slot,
    pageWidth,
    pageHeight,
    onPanStart,
}: {
    pageId: string;
    slot: PhotoSlot;
    pageWidth: number;
    pageHeight: number;
    onPanStart: (event: React.MouseEvent, slot: PhotoSlot) => void;
}) {
    const { updateSlot, removeSlot } = useBook("updateSlot", "removeSlot");
    const [panning, setPanning] = useState(false);
    const buttonSize = Math.max(32, Math.min(38, pageWidth * 0.08));
    const toolbarWidth = buttonSize * 5 + 34;
    const slotLeft = (slot.x / 100) * pageWidth;
    const center = ((slot.x + slot.width / 2) / 100) * pageWidth;
    const toolbarLeft =
        Math.max(
            toolbarWidth / 2 + 4,
            Math.min(pageWidth - toolbarWidth / 2 - 4, center),
        ) - slotLeft;
    const buttonSx = {
        width: buttonSize,
        height: buttonSize,
        p: 0,
        borderRadius: "12px",
        color: toolbarColors.text,
        "&:hover": { bgcolor: toolbarColors.hover },
        "&.Mui-disabled": { color: toolbarColors.disabled },
        "& .MuiSvgIcon-root": { fontSize: 20 },
    };

    return (
        <Box
            sx={{
                position: "absolute",
                left: slotLeft,
                top: (slot.y / 100) * pageHeight,
                width: (slot.width / 100) * pageWidth,
                height: (slot.height / 100) * pageHeight,
                zIndex: 5,
                pointerEvents: "none",
            }}
        >
            {panning && (
                <Box
                    onMouseDown={(event) => onPanStart(event, slot)}
                    sx={{
                        position: "absolute",
                        inset: 0,
                        cursor: "move",
                        pointerEvents: "auto",
                    }}
                />
            )}
            <Box
                data-page-control
                data-open="true"
                role="toolbar"
                aria-label="Photo tools"
                onMouseDown={(event) => event.stopPropagation()}
                onClick={(event) => event.stopPropagation()}
                sx={{
                    position: "absolute",
                    left: toolbarLeft,
                    bottom: 0,
                    transform: "translate(-50%, 50%)",
                    display: "flex",
                    alignItems: "center",
                    gap: "3px",
                    p: "6px",
                    borderRadius: "18px",
                    bgcolor: toolbarColors.background,
                    boxShadow: popupShadow,
                    pointerEvents: "auto",
                }}
            >
                <Tooltip title={panning ? "Finish panning" : "Pan photo"}>
                    <IconButton
                        aria-label="Pan photo"
                        aria-pressed={panning}
                        onClick={() => setPanning((active) => !active)}
                        sx={{
                            ...buttonSx,
                            ...(panning && {
                                color: accentGreen,
                                bgcolor: "rgba(8,194,37,0.18)",
                                "&:hover": { bgcolor: "rgba(8,194,37,0.26)" },
                            }),
                        }}
                    >
                        <PanIcon />
                    </IconButton>
                </Tooltip>
                <Tooltip title="Zoom out">
                    <span style={{ display: "flex" }}>
                        <IconButton
                            aria-label="Zoom out"
                            disabled={slot.cropZoom <= 1}
                            onClick={() =>
                                updateSlot(pageId, slot.id, {
                                    cropZoom: Math.max(
                                        1,
                                        Math.round((slot.cropZoom - 0.2) * 10) /
                                            10,
                                    ),
                                })
                            }
                            sx={buttonSx}
                        >
                            <ZoomOutIcon />
                        </IconButton>
                    </span>
                </Tooltip>
                <Tooltip title="Zoom in">
                    <span style={{ display: "flex" }}>
                        <IconButton
                            aria-label="Zoom in"
                            disabled={slot.cropZoom >= 3}
                            onClick={() =>
                                updateSlot(pageId, slot.id, {
                                    cropZoom: Math.min(
                                        3,
                                        Math.round((slot.cropZoom + 0.2) * 10) /
                                            10,
                                    ),
                                })
                            }
                            sx={buttonSx}
                        >
                            <ZoomInIcon />
                        </IconButton>
                    </span>
                </Tooltip>
                <Tooltip title="Rotate 90°">
                    <IconButton
                        aria-label="Rotate photo 90 degrees clockwise"
                        onClick={() =>
                            updateSlot(pageId, slot.id, {
                                rotation: ((slot.rotation ?? 0) + 90) % 360,
                                cropX: 1 - slot.cropY,
                                cropY: slot.cropX,
                            })
                        }
                        sx={buttonSx}
                    >
                        <RotatePhotoIcon />
                    </IconButton>
                </Tooltip>
                <Box
                    aria-hidden
                    sx={{
                        width: "1px",
                        height: 24,
                        mx: "3px",
                        bgcolor: toolbarColors.border,
                    }}
                />
                <Tooltip title="Remove from page">
                    <IconButton
                        aria-label="Remove photo from page"
                        onClick={() => removeSlot(pageId, slot.id)}
                        sx={{
                            ...buttonSx,
                            "&:hover": {
                                color: pageMenuColors.danger,
                                bgcolor: pageMenuColors.dangerHover,
                            },
                        }}
                    >
                        <DeleteIcon />
                    </IconButton>
                </Tooltip>
            </Box>
        </Box>
    );
}
