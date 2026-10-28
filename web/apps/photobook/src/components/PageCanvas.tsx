"use client";

import { useBook } from "@/context/book";
import {
    getCachedImage,
    getCachedUrl,
    loadImageCached,
} from "@/lib/imageCache";
import {
    CAPTION_FONT_WEIGHT,
    CENTER_TEXT_FONT_WEIGHT,
    getBrandingLayout,
    getCaptionLayout,
    getCenterTextLayout,
    getInterFont,
    getOutfitFont,
    getTextBlockLayout,
    SAFE_AREA,
    TEXT_LINE_HEIGHT,
    type CaptionLayout,
} from "@/lib/printLayout";
import type { BookPage, PhotoSlot, TextBlock } from "@/lib/types";
import Konva from "konva";
import { useEffect, useMemo, useState } from "react";
import { Group, Image as KonvaImage, Rect, Text } from "react-konva";

export type CaptionPosition = "top" | "bottom";

interface PageCanvasProps {
    page: BookPage;
    pageWidth: number;
    pageHeight: number;
    isBackCover?: boolean;
    isFrontCover?: boolean;
    photoUrls?: Map<string, string>;
    onSlotClick?: (slotId: string) => void;
    selectedSlotId?: string | null;
    selectedTextId?: string | null;
    editingTextId?: string | null;
    editingCaption?: CaptionPosition | null;
    hideCaptions?: boolean;
    hideCenterText?: boolean;
    dragOverSlotId?: string | null;
    dragSourceSlotId?: string | null;
}

function PhotoSlotRenderer({
    slot,
    pageWidth,
    pageHeight,
    photoUrl,
    isSelected,
    isDragOver,
    isDragSource,
    onClick,
}: {
    slot: PhotoSlot;
    pageWidth: number;
    pageHeight: number;
    photoUrl?: string;
    isSelected: boolean;
    isDragOver: boolean;
    isDragSource: boolean;
    onClick: () => void;
}) {
    // Initialize from the shared cache so re-mounts (virtualization churn in
    // EditPage) draw the photo on the first paint instead of flashing white.
    const photoId = slot.photoId;
    const [image, setImage] = useState<HTMLImageElement | null>(() =>
        photoId ? getCachedImage(photoId) : null,
    );

    const sx = (slot.x / 100) * pageWidth;
    const sy = (slot.y / 100) * pageHeight;
    const sw = (slot.width / 100) * pageWidth;
    const sh = (slot.height / 100) * pageHeight;

    useEffect(() => {
        if (!photoId || !photoUrl) {
            setImage(null);
            return;
        }
        // Show whatever is in the cache immediately (may be a lower-res thumb
        // while the preview loads — prevents blank flash on remount).
        const cached = getCachedImage(photoId);
        if (cached) setImage(cached);

        // If the cached image was loaded from this exact URL, we're done.
        // Otherwise load the new URL (handles thumb → preview upgrade).
        if (cached && getCachedUrl(photoId) === photoUrl) return;

        let cancelled = false;
        loadImageCached(photoId, photoUrl)
            .then((img) => {
                if (!cancelled) setImage(img);
            })
            .catch(() => {
                // Only blank the slot if we had nothing to show
                if (!cancelled && !cached) setImage(null);
            });
        return () => {
            cancelled = true;
        };
    }, [photoId, photoUrl]);

    const clipFunc = (ctx: Konva.Context) => {
        ctx.rect(sx, sy, sw, sh);
    };

    // Calculate image draw position (cover-fit inside the slot, shifted by crop).
    const drawProps = useMemo(() => {
        if (!image) return null;
        const imgAspect = image.naturalWidth / image.naturalHeight;
        const slotAspect = sw / sh;

        let drawW: number, drawH: number;
        if (imgAspect > slotAspect) {
            drawH = sh * slot.cropZoom;
            drawW = drawH * imgAspect;
        } else {
            drawW = sw * slot.cropZoom;
            drawH = drawW / imgAspect;
        }

        const drawX = sx + (sw - drawW) * slot.cropX;
        const drawY = sy + (sh - drawH) * slot.cropY;

        return { x: drawX, y: drawY, width: drawW, height: drawH };
    }, [image, sx, sy, sw, sh, slot.cropX, slot.cropY, slot.cropZoom]);

    return (
        <Group clipFunc={clipFunc}>
            {/* Slot background */}
            <Rect
                x={sx}
                y={sy}
                width={sw}
                height={sh}
                fill="#EEEEF0"
                onClick={onClick}
                onTap={onClick}
            />
            {/* Photo — non-interactive. Crop panning is handled by an HTML overlay
          in SpreadPage.tsx (see the slot overlay's onMouseDown). Running drag
          inside Konva was unreliable in Chromium on Linux due to event
          layering between the stacked <div> overlays and the canvas. */}
            {image && drawProps && (
                <KonvaImage
                    image={image}
                    x={drawProps.x}
                    y={drawProps.y}
                    width={drawProps.width}
                    height={drawProps.height}
                    listening={false}
                />
            )}
            {/* Drag source dimming */}
            {isDragSource && (
                <Rect
                    x={sx}
                    y={sy}
                    width={sw}
                    height={sh}
                    fill="rgba(255, 255, 255, 0.5)"
                    listening={false}
                />
            )}
            {/* Drag over indicator */}
            {isDragOver && !isDragSource && (
                <Rect
                    x={sx}
                    y={sy}
                    width={sw}
                    height={sh}
                    stroke="#08C225"
                    strokeWidth={2}
                    dash={[6, 3]}
                    fill="rgba(8, 194, 37, 0.1)"
                    listening={false}
                />
            )}
            {/* Selection border */}
            {isSelected && !isDragSource && (
                <Rect
                    x={sx}
                    y={sy}
                    width={sw}
                    height={sh}
                    stroke="#08C225"
                    strokeWidth={4}
                    listening={false}
                />
            )}
            {/* Empty slot indicator */}
            {!image && !slot.photoId && (
                <Text
                    x={sx}
                    y={sy + sh / 2 - 8}
                    width={sw}
                    text={isDragOver ? "Drop here" : "Empty slot"}
                    fontSize={12}
                    fontFamily={getInterFont()}
                    fill={isDragOver ? "#08C225" : "#999"}
                    fontStyle={isDragOver ? "bold" : "normal"}
                    align="center"
                />
            )}
        </Group>
    );
}

function TextBlockRenderer({
    block,
    pageWidth,
    pageHeight,
    isSelected,
    isEditing,
}: {
    block: TextBlock;
    pageWidth: number;
    pageHeight: number;
    isSelected: boolean;
    isEditing: boolean;
}) {
    const layout = getTextBlockLayout(block);
    const bx = (layout.x / 100) * pageWidth;
    const by = (layout.y / 100) * pageHeight;
    const bw = (layout.width / 100) * pageWidth;
    const bh = (layout.height / 100) * pageHeight;

    const fontSize = pageHeight * (layout.fontSize / 100);
    const color = block.color ?? "#555555";
    const rotation = layout.rotation;

    // Hide text while inline editing
    if (isEditing) return null;

    const displayText = block.text || (isSelected ? "" : "Type here");
    const displayColor = block.text ? color : "#bbb";

    return (
        <Group x={bx} y={by} rotation={rotation}>
            <Text
                x={(layout.padding / 100) * pageWidth}
                y={0}
                text={displayText}
                fontSize={fontSize}
                fontFamily={getInterFont()}
                fontStyle="bold"
                fill={displayColor}
                lineHeight={TEXT_LINE_HEIGHT}
                verticalAlign="middle"
                wrap="none"
                listening={false}
            />
            {isSelected && (
                <Rect
                    x={-3}
                    y={-3}
                    width={bw + 6}
                    height={bh + 6}
                    stroke="#08C225"
                    strokeWidth={3}
                    listening={false}
                />
            )}
        </Group>
    );
}

function EnteBranding({
    pageWidth,
    pageHeight,
}: {
    pageWidth: number;
    pageHeight: number;
}) {
    const [logo, setLogo] = useState<HTMLCanvasElement | null>(null);

    useEffect(() => {
        const img = new window.Image();
        img.onload = () => {
            // Pre-scale to target size in an offscreen canvas to avoid
            // aliasing from extreme downscaling (1024px → ~60px).
            const targetH = Math.round(
                pageHeight * 0.031 * (window.devicePixelRatio || 1),
            );
            const targetW = Math.round(
                (img.naturalWidth / img.naturalHeight) * targetH,
            );
            const offscreen = document.createElement("canvas");
            offscreen.width = targetW;
            offscreen.height = targetH;
            const ctx = offscreen.getContext("2d")!;
            ctx.imageSmoothingEnabled = true;
            ctx.imageSmoothingQuality = "high";
            ctx.drawImage(img, 0, 0, targetW, targetH);
            setLogo(offscreen);
        };
        img.src = "/ente-branding.svg";
    }, [pageHeight]);

    const layout = getBrandingLayout();

    return (
        <>
            {logo && (
                <KonvaImage
                    image={logo}
                    x={(layout.x / 100) * pageWidth}
                    y={(layout.y / 100) * pageHeight}
                    width={(layout.width / 100) * pageWidth}
                    height={(layout.height / 100) * pageHeight}
                    listening={false}
                />
            )}
        </>
    );
}

function CaptionText({
    text,
    layout,
    pageWidth,
    pageHeight,
    isEditing,
    lineHeight = TEXT_LINE_HEIGHT,
    fontFamily = getInterFont(),
    fontWeight = CAPTION_FONT_WEIGHT,
}: {
    text: string;
    layout: CaptionLayout | null;
    pageWidth: number;
    pageHeight: number;
    isEditing?: boolean;
    lineHeight?: number;
    fontFamily?: string;
    fontWeight?: number;
}) {
    // Hide rendered text while editing (HTML overlay replaces it)
    if (isEditing) return null;
    if (!text) return null;
    // No room for the caption (e.g. a full-bleed photo touches the page edge).
    // Stale captions from a previous layout would otherwise spill off the page.
    if (!layout) return null;
    const x = (layout.x / 100) * pageWidth;
    const y = (layout.y / 100) * pageHeight;
    const width = (layout.width / 100) * pageWidth;
    const height = (layout.height / 100) * pageHeight;
    return (
        <Group clipX={x} clipY={y} clipWidth={width} clipHeight={height}>
            <Text
                x={x}
                y={y}
                width={width}
                height={height}
                text={text}
                fontSize={(layout.fontSize / 100) * pageHeight}
                lineHeight={lineHeight}
                wrap="none"
                fontFamily={fontFamily}
                fontStyle={String(fontWeight)}
                fill="#2a2a2a"
                align="center"
                verticalAlign="middle"
            />
        </Group>
    );
}

export default function PageCanvas({
    page,
    pageWidth,
    pageHeight,
    isBackCover = false,
    isFrontCover = false,
    selectedSlotId,
    selectedTextId,
    dragOverSlotId,
    dragSourceSlotId,
    onSlotClick,
    editingTextId,
    editingCaption,
    hideCaptions = false,
    hideCenterText = false,
    photoUrls: photoUrlsProp,
}: PageCanvasProps) {
    const { thumbnailUrls } = useBook();
    const urls = photoUrlsProp ?? thumbnailUrls;

    const [, setFontsReady] = useState(false);
    useEffect(() => {
        let active = true;
        void document.fonts.ready.then(() => {
            if (active) setFontsReady(true);
        });
        return () => {
            active = false;
        };
    }, []);
    const topCaption = getCaptionLayout(page, "top", isFrontCover);
    const bottomCaption = getCaptionLayout(page, "bottom", isFrontCover);
    const centerText = getCenterTextLayout(page);

    return (
        <>
            {/* White page background */}
            <Rect
                x={0}
                y={0}
                width={pageWidth}
                height={pageHeight}
                fill="#ffffff"
                listening={false}
            />

            {/* Photo slots */}
            {page.slots.map((slot) => (
                <PhotoSlotRenderer
                    key={slot.id}
                    slot={slot}
                    pageWidth={pageWidth}
                    pageHeight={pageHeight}
                    photoUrl={slot.photoId ? urls.get(slot.photoId) : undefined}
                    isSelected={selectedSlotId === slot.id}
                    isDragOver={dragOverSlotId === slot.id}
                    isDragSource={dragSourceSlotId === slot.id}
                    onClick={() => onSlotClick?.(slot.id)}
                />
            ))}

            {/* Captions — centered in the safe part of each photo margin. */}
            {!hideCenterText && page.centerText && (
                <CaptionText
                    text={centerText?.lines.join("\n") ?? ""}
                    layout={centerText}
                    pageWidth={pageWidth}
                    pageHeight={pageHeight}
                    lineHeight={centerText?.lineHeight}
                    fontFamily={getOutfitFont()}
                    fontWeight={CENTER_TEXT_FONT_WEIGHT}
                />
            )}
            {!hideCaptions && (
                <CaptionText
                    text={page.topCaption}
                    layout={topCaption}
                    pageWidth={pageWidth}
                    pageHeight={pageHeight}
                    isEditing={editingCaption === "top"}
                    fontFamily={isFrontCover ? getOutfitFont() : getInterFont()}
                    fontWeight={
                        isFrontCover
                            ? CENTER_TEXT_FONT_WEIGHT
                            : CAPTION_FONT_WEIGHT
                    }
                />
            )}
            {isBackCover ? (
                <EnteBranding pageWidth={pageWidth} pageHeight={pageHeight} />
            ) : (
                !hideCaptions && (
                    <CaptionText
                        text={page.bottomCaption}
                        layout={bottomCaption}
                        pageWidth={pageWidth}
                        pageHeight={pageHeight}
                        isEditing={editingCaption === "bottom"}
                        fontFamily={
                            isFrontCover ? getOutfitFont() : getInterFont()
                        }
                        fontWeight={
                            isFrontCover
                                ? CENTER_TEXT_FONT_WEIGHT
                                : CAPTION_FONT_WEIGHT
                        }
                    />
                )
            )}

            {/* Text blocks */}
            <Group
                clipX={(SAFE_AREA.x / 100) * pageWidth}
                clipY={(SAFE_AREA.y / 100) * pageHeight}
                clipWidth={(SAFE_AREA.width / 100) * pageWidth}
                clipHeight={(SAFE_AREA.height / 100) * pageHeight}
            >
                {page.textBlocks.map((block) => (
                    <TextBlockRenderer
                        key={block.id}
                        block={block}
                        pageWidth={pageWidth}
                        pageHeight={pageHeight}
                        isSelected={selectedTextId === block.id}
                        isEditing={editingTextId === block.id}
                    />
                ))}
            </Group>

            {/* Page number */}
            <Text
                x={pageWidth - 30}
                y={pageHeight - 18}
                text=""
                fontSize={8}
                fill="#ccc"
                fontFamily={getInterFont()}
            />
        </>
    );
}
