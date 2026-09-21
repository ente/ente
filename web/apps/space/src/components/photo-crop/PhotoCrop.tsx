import { Box } from "@mui/material";
import React from "react";
import type { SpaceImageCropArea } from "utils/post-image";
import {
    moveImageCrop,
    resizeImageCrop,
    rotatedImageSize,
    type CropHandle,
    type ImageSize,
} from "./geometry";

const handles: { handle: CropHandle; label: string; x: number; y: number }[] = [
    { handle: "nw", label: "top left", x: 0, y: 0 },
    { handle: "n", label: "top", x: 50, y: 0 },
    { handle: "ne", label: "top right", x: 100, y: 0 },
    { handle: "e", label: "right", x: 100, y: 50 },
    { handle: "se", label: "bottom right", x: 100, y: 100 },
    { handle: "s", label: "bottom", x: 50, y: 100 },
    { handle: "sw", label: "bottom left", x: 0, y: 100 },
    { handle: "w", label: "left", x: 0, y: 50 },
];

export const SpacePhotoCrop: React.FC<{
    imageURL: string;
    imageSize: ImageSize;
    rotation: number;
    crop: SpaceImageCropArea;
    aspect?: number;
    disabled: boolean;
    onChange: (crop: SpaceImageCropArea) => void;
}> = ({ imageURL, imageSize, rotation, crop, aspect, disabled, onChange }) => {
    const containerRef = React.useRef<HTMLDivElement>(null);
    const [available, setAvailable] = React.useState({ width: 0, height: 0 });
    const gesture = React.useRef<{
        pointerID: number;
        x: number;
        y: number;
        crop: SpaceImageCropArea;
        handle?: CropHandle;
    }>(undefined);
    const size = rotatedImageSize(imageSize, rotation);
    const scale = Math.min(
        available.width / size.width,
        available.height / size.height,
    );
    const cropStyle = {
        left: `${(crop.x / size.width) * 100}%`,
        top: `${(crop.y / size.height) * 100}%`,
        width: `${(crop.width / size.width) * 100}%`,
        height: `${(crop.height / size.height) * 100}%`,
    };

    React.useEffect(() => {
        const observer = new ResizeObserver(([entry]) => {
            if (entry)
                setAvailable({
                    width: entry.contentRect.width,
                    height: entry.contentRect.height,
                });
        });
        observer.observe(containerRef.current!);
        return () => observer.disconnect();
    }, []);

    const change = (
        start: SpaceImageCropArea,
        dx: number,
        dy: number,
        handle?: CropHandle,
    ) =>
        onChange(
            handle
                ? resizeImageCrop(
                      start,
                      handle,
                      dx / scale,
                      dy / scale,
                      size,
                      24 / scale,
                      aspect,
                  )
                : moveImageCrop(start, dx / scale, dy / scale, size),
        );

    const start = (
        event: React.PointerEvent<HTMLElement>,
        handle?: CropHandle,
    ) => {
        if (disabled || !event.isPrimary || event.button != 0) return;
        event.preventDefault();
        event.stopPropagation();
        event.currentTarget.focus({ preventScroll: true });
        event.currentTarget.setPointerCapture(event.pointerId);
        gesture.current = {
            pointerID: event.pointerId,
            x: event.clientX,
            y: event.clientY,
            crop,
            handle,
        };
    };
    const keyDown = (event: React.KeyboardEvent, handle?: CropHandle) => {
        if (
            disabled ||
            !["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(
                event.key,
            )
        )
            return;
        event.preventDefault();
        event.stopPropagation();
        const step = event.shiftKey ? 10 : 1;
        change(
            crop,
            event.key == "ArrowLeft"
                ? -step
                : event.key == "ArrowRight"
                  ? step
                  : 0,
            event.key == "ArrowUp"
                ? -step
                : event.key == "ArrowDown"
                  ? step
                  : 0,
            handle,
        );
    };

    return (
        <Box
            ref={containerRef}
            sx={{
                alignItems: "center",
                display: "flex",
                flex: 1,
                justifyContent: "center",
                minHeight: 0,
                width: "100%",
            }}
        >
            {scale > 0 && (
                <Box
                    onPointerMove={(event) => {
                        const active = gesture.current;
                        if (active?.pointerID != event.pointerId) return;
                        change(
                            active.crop,
                            event.clientX - active.x,
                            event.clientY - active.y,
                            active.handle,
                        );
                    }}
                    onPointerUp={() => {
                        gesture.current = undefined;
                    }}
                    onPointerCancel={() => {
                        gesture.current = undefined;
                    }}
                    onLostPointerCapture={() => {
                        gesture.current = undefined;
                    }}
                    sx={{
                        width: size.width * scale,
                        height: size.height * scale,
                        position: "relative",
                        touchAction: "none",
                        userSelect: "none",
                    }}
                >
                    <Box
                        sx={{
                            position: "absolute",
                            inset: 0,
                            overflow: "hidden",
                        }}
                    >
                        <Box
                            component="img"
                            src={imageURL}
                            alt="Photo to crop"
                            draggable={false}
                            sx={{
                                position: "absolute",
                                left: "50%",
                                top: "50%",
                                width: imageSize.width * scale,
                                height: imageSize.height * scale,
                                maxWidth: "none",
                                transform: `translate(-50%, -50%) rotate(${rotation}deg)`,
                                pointerEvents: "none",
                            }}
                        />
                        <Box
                            style={cropStyle}
                            sx={{
                                position: "absolute",
                                boxShadow: "0 0 0 9999px rgba(0,0,0,0.6)",
                                pointerEvents: "none",
                            }}
                        />
                    </Box>
                    <Box
                        role="group"
                        aria-label="Crop selection"
                        aria-description="Use arrow keys to move the crop. Hold Shift for larger steps."
                        tabIndex={disabled ? -1 : 0}
                        onPointerDown={(event) => start(event)}
                        onKeyDown={(event) => keyDown(event)}
                        style={cropStyle}
                        sx={{
                            position: "absolute",
                            boxSizing: "border-box",
                            border: "1px solid white",
                            cursor: "move",
                            "&:focus-visible": {
                                outline: "2px solid #08C225",
                                outlineOffset: 2,
                            },
                        }}
                    >
                        {[1, 2].map((line) => (
                            <React.Fragment key={line}>
                                <Box
                                    sx={{
                                        position: "absolute",
                                        left: `${(line * 100) / 3}%`,
                                        top: 0,
                                        bottom: 0,
                                        borderLeft:
                                            "1px solid rgba(255,255,255,0.35)",
                                        pointerEvents: "none",
                                    }}
                                />
                                <Box
                                    sx={{
                                        position: "absolute",
                                        top: `${(line * 100) / 3}%`,
                                        left: 0,
                                        right: 0,
                                        borderTop:
                                            "1px solid rgba(255,255,255,0.35)",
                                        pointerEvents: "none",
                                    }}
                                />
                            </React.Fragment>
                        ))}
                        {handles
                            .filter(
                                ({ handle }) => !aspect || handle.length == 2,
                            )
                            .map(({ handle, label, x, y }) => (
                                <Box
                                    key={handle}
                                    component="button"
                                    type="button"
                                    disabled={disabled}
                                    aria-label={`Resize crop ${label}`}
                                    aria-description="Use arrow keys to resize the crop. Hold Shift for larger steps."
                                    onPointerDown={(event) =>
                                        start(event, handle)
                                    }
                                    onKeyDown={(event) =>
                                        keyDown(event, handle)
                                    }
                                    sx={{
                                        position: "absolute",
                                        left: `${x}%`,
                                        top: `${y}%`,
                                        transform: "translate(-50%, -50%)",
                                        width:
                                            handle.length == 1 && y != 50
                                                ? "calc(100% - 32px)"
                                                : 32,
                                        height:
                                            handle.length == 1 && x != 50
                                                ? "calc(100% - 32px)"
                                                : 32,
                                        minWidth: 16,
                                        minHeight: 16,
                                        bgcolor: "transparent",
                                        border: 0,
                                        p: 0,
                                        cursor: `${handle}-resize`,
                                        touchAction: "none",
                                        "&:focus-visible": {
                                            outline: "2px solid #08C225",
                                        },
                                        "&::after": {
                                            content: '""',
                                            position: "absolute",
                                            left: "50%",
                                            top: "50%",
                                            transform: "translate(-50%, -50%)",
                                            width:
                                                handle.length == 2
                                                    ? 10
                                                    : y == 50
                                                      ? 3
                                                      : 16,
                                            height:
                                                handle.length == 2
                                                    ? 10
                                                    : x == 50
                                                      ? 3
                                                      : 16,
                                            bgcolor: "white",
                                            boxShadow:
                                                "0 0 2px rgba(0,0,0,0.8)",
                                        },
                                    }}
                                />
                            ))}
                    </Box>
                </Box>
            )}
        </Box>
    );
};
