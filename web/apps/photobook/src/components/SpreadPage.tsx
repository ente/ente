"use client";

import { bookPageShadow, uiColors } from "@/theme/colors";

import { useBook } from "@/context/book";
import type { DragInfo } from "@/hooks/usePhotoDrag";
import { isRequiredBlankPage } from "@/lib/bookPages";
import {
    CAPTION_FONT_WEIGHT,
    CENTER_TEXT_FONT_WEIGHT,
    getCaptionLayout,
    getCenterTextLayout,
    getTextBlockLayout,
    TEXT_LINE_HEIGHT,
} from "@/lib/printLayout";
import type { BookPage, TextBlock } from "@/lib/types";
import { Box, Button, Typography } from "@mui/material";
import React, { useEffect, useMemo, useRef, useState } from "react";
import { Layer, Stage } from "react-konva";
import { AddPhotosIcon, DeleteIcon, ZoomInIcon, ZoomOutIcon } from "./icons";
import LayoutPicker from "./LayoutPicker";
import type { CaptionPosition } from "./PageCanvas";
import PageCanvas from "./PageCanvas";
import PageMenu, { type PageInsertPosition } from "./PageMenu";
import styles from "./SpreadPage.module.css";
import TextToolbar from "./TextToolbar";

function SlotControls({
    pageId,
    slotId,
    slot,
    pageWidth,
    pageHeight,
}: {
    pageId: string;
    slotId: string;
    slot: {
        x: number;
        y: number;
        width: number;
        height: number;
        cropZoom: number;
    };
    pageWidth: number;
    pageHeight: number;
}) {
    const { updateSlot, removeSlot } = useBook();

    const handleZoomIn = (e: React.MouseEvent) => {
        e.stopPropagation();
        updateSlot(pageId, slotId, {
            cropZoom: Math.min(slot.cropZoom + 0.2, 3),
        });
    };

    const handleZoomOut = (e: React.MouseEvent) => {
        e.stopPropagation();
        updateSlot(pageId, slotId, {
            cropZoom: Math.max(slot.cropZoom - 0.2, 1),
        });
    };

    const handleDelete = (e: React.MouseEvent) => {
        e.stopPropagation();
        removeSlot(pageId, slotId);
    };

    const btnSize = Math.max(22, Math.min(28, pageWidth * 0.06));
    const iconSize = btnSize * 0.58;
    const padding = Math.max(4, pageWidth * 0.012);

    return (
        <div
            style={{
                position: "absolute",
                left: (slot.x / 100) * pageWidth,
                top: (slot.y / 100) * pageHeight,
                width: (slot.width / 100) * pageWidth,
                height: (slot.height / 100) * pageHeight,
                zIndex: 3,
                pointerEvents: "none",
            }}
        >
            {/* Delete — top right */}
            <div
                className={styles.hoverControl}
                onClick={handleDelete}
                style={{
                    position: "absolute",
                    top: padding,
                    right: padding,
                    width: btnSize,
                    height: btnSize,
                    borderRadius: btnSize / 2,
                    background: "rgba(0,0,0,0.45)",
                    backdropFilter: "blur(8px)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    cursor: "pointer",
                }}
                onMouseEnter={(e) => {
                    e.currentTarget.style.background = "rgba(186,26,26,0.7)";
                }}
                onMouseLeave={(e) => {
                    e.currentTarget.style.background = "rgba(0,0,0,0.45)";
                }}
            >
                <DeleteIcon
                    sx={{ fontSize: iconSize, color: "rgba(255,255,255,0.9)" }}
                />
            </div>

            {/* Zoom controls — bottom right */}
            <div
                className={styles.hoverControl}
                style={{
                    position: "absolute",
                    bottom: padding,
                    right: padding,
                    display: "flex",
                    gap: 2,
                    borderRadius: btnSize / 2,
                    background: "rgba(0,0,0,0.45)",
                    backdropFilter: "blur(8px)",
                    padding: 2,
                }}
            >
                <div
                    onClick={handleZoomOut}
                    style={{
                        width: btnSize,
                        height: btnSize,
                        borderRadius: btnSize / 2,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        cursor: "pointer",
                        transition: "background 0.15s",
                    }}
                    onMouseEnter={(e) => {
                        e.currentTarget.style.background =
                            "rgba(255,255,255,0.15)";
                    }}
                    onMouseLeave={(e) => {
                        e.currentTarget.style.background = "transparent";
                    }}
                >
                    <ZoomOutIcon
                        sx={{
                            fontSize: iconSize,
                            color: "rgba(255,255,255,0.9)",
                        }}
                    />
                </div>
                <div
                    onClick={handleZoomIn}
                    style={{
                        width: btnSize,
                        height: btnSize,
                        borderRadius: btnSize / 2,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        cursor: "pointer",
                        transition: "background 0.15s",
                    }}
                    onMouseEnter={(e) => {
                        e.currentTarget.style.background =
                            "rgba(255,255,255,0.15)";
                    }}
                    onMouseLeave={(e) => {
                        e.currentTarget.style.background = "transparent";
                    }}
                >
                    <ZoomInIcon
                        sx={{
                            fontSize: iconSize,
                            color: "rgba(255,255,255,0.9)",
                        }}
                    />
                </div>
            </div>
        </div>
    );
}

export const PICKER_WIDTH = 60;

interface SpreadPageProps {
    page: BookPage;
    pageIndex: number;
    pickerSide: "left" | "right";
    pageWidth: number;
    pageHeight: number;
    totalPages: number;
    // Selection
    selectedSlotId: string | null;
    selectedPageId: string | null;
    selectedTextId: string | null;
    editingTextId: string | null;
    onSlotClick: (pageId: string, slotId: string) => void;
    onTextClick: (pageId: string, textId: string) => void;
    onTextDblClick: (pageId: string, textId: string) => void;
    onTextUpdate: (
        pageId: string,
        blockId: string,
        updates: Partial<TextBlock>,
    ) => void;
    onTextDelete: (pageId: string, blockId: string) => void;
    onTextEditEnd: () => void;
    onClearSelection: () => void;
    onInsertPage: (pageIndex: number, position: PageInsertPosition) => void;
    onAddPhotos: (pageId: string) => void;
    // Photo drag
    dragSourceInfo: DragInfo | null;
    dragOverInfo: DragInfo | null;
    dragOverPageId: string | null;
    onPhotoDragStart: (
        e: React.DragEvent,
        pageId: string,
        slotId: string,
        photoId: string,
    ) => void;
    onSlotDragOver: (
        e: React.DragEvent,
        pageId: string,
        slotId: string,
    ) => void;
    onPhotoDrop: (e: React.DragEvent, pageId: string, slotId: string) => void;
    onPhotoDragEnd: () => void;
    onPageDragOver: (e: React.DragEvent, pageId: string) => void;
    onPageDrop: (e: React.DragEvent, pageId: string) => void;
    // Page drag
    pageDragSource: number | null;
    pageDragTarget: number | null;
    pageDragSourceRef: React.RefObject<number | null>;
    onPageDragStart: (e: React.DragEvent, pageIndex: number) => void;
    onPageDragOverPage: (e: React.DragEvent, pageIndex: number) => void;
    onPageDropOnPage: (e: React.DragEvent, pageIndex: number) => void;
    onPageDragEndCleanup: () => void;
}

export default function SpreadPage({
    page,
    pageIndex,
    pickerSide,
    pageWidth,
    pageHeight,
    totalPages,
    selectedSlotId,
    selectedPageId,
    selectedTextId,
    editingTextId,
    onSlotClick,
    onTextClick,
    onTextDblClick,
    onTextUpdate,
    onTextDelete,
    onTextEditEnd,
    onClearSelection,
    onInsertPage,
    onAddPhotos,
    dragSourceInfo,
    dragOverInfo,
    dragOverPageId,
    onPhotoDragStart,
    onSlotDragOver,
    onPhotoDrop,
    onPhotoDragEnd,
    onPageDragOver,
    onPageDrop,
    pageDragSource,
    pageDragTarget,
    pageDragSourceRef,
    onPageDragStart,
    onPageDragOverPage,
    onPageDropOnPage,
    onPageDragEndCleanup,
}: SpreadPageProps) {
    const {
        book,
        thumbnailUrls,
        photoUrls,
        loadPreviews,
        removePage,
        setPageLayout,
        updatePage,
        updateSlot,
        photos,
        processingPhotos,
    } = useBook();

    // Trigger lazy-loading of 1080px previews for this page's photos
    const pagePhotoIds = useMemo(
        () => page.slots.filter((s) => s.photoId).map((s) => s.photoId!),
        [page.slots],
    );
    useEffect(() => {
        if (pagePhotoIds.length > 0)
            void loadPreviews(pagePhotoIds).catch((error: unknown) =>
                console.error("Failed to load previews", error),
            );
    }, [pagePhotoIds, loadPreviews]);

    // Caption editing
    const [editingCaption, setEditingCaption] =
        useState<CaptionPosition | null>(null);
    const [captionValue, setCaptionValue] = useState("");
    const captionInputRef = useRef<HTMLInputElement>(null);
    const [editingCenterText, setEditingCenterText] = useState(false);
    const [centerTextDraft, setCenterTextDraft] = useState("");
    const [textDraft, setTextDraft] = useState<{
        id: string;
        value: string;
    } | null>(null);

    useEffect(() => {
        if (!editingTextId) setTextDraft(null);
    }, [editingTextId]);

    const isBackCover = pageIndex === totalPages - 1;
    const isFrontCover = pageIndex === 0;

    const handleCaptionClick = (position: CaptionPosition) => {
        onClearSelection();
        const val = position === "top" ? page.topCaption : page.bottomCaption;
        setCaptionValue(val);
        setEditingCaption(position);
    };

    const handleCaptionSave = () => {
        if (editingCaption) {
            const key =
                editingCaption === "top" ? "topCaption" : "bottomCaption";
            updatePage(page.id, { [key]: captionValue });
            setEditingCaption(null);
        }
    };

    const handleCaptionCancel = () => {
        handleCaptionSave();
    };

    useEffect(() => {
        if (editingCaption && captionInputRef.current) {
            captionInputRef.current.focus();
            captionInputRef.current.select();
        }
    }, [editingCaption]);

    const isInterior = pageIndex > 0 && !isBackCover;
    const isDragTarget =
        pageDragTarget === pageIndex && pageDragSource !== null;
    const isDragSource = pageDragSource === pageIndex;
    const photoCount = page.slots.filter((s) => s.photoId !== null).length;
    const showEmptyPageAddPhotos =
        isInterior &&
        photoCount === 0 &&
        page.textBlocks.length === 0 &&
        !(editingCenterText ? centerTextDraft : (page.centerText ?? "")).trim();
    useEffect(() => {
        if (photoCount > 0) setEditingCenterText(false);
        else setEditingCaption(null);
    }, [photoCount]);
    // The photo-free back cover has no photo layout choices.
    const hideLayoutPicker = isBackCover;
    const hasSelectedSlotOnPage =
        selectedPageId === page.id && selectedSlotId !== null;

    const pageBlock = (
        <Box>
            <Box
                data-book-page={page.id}
                sx={{
                    position: "relative",
                    bgcolor: uiColors.paper,
                    boxShadow: isDragTarget
                        ? `0 0 0 3px #08C225, ${bookPageShadow}`
                        : bookPageShadow,
                    borderRadius: 0.5,
                    overflow: "hidden",
                    opacity: isDragSource ? 0.4 : 1,
                    transition: "box-shadow 0.15s, opacity 0.15s",
                }}
            >
                <Stage
                    width={pageWidth}
                    height={pageHeight}
                    onClick={(e) => {
                        if (e.target === e.target.getStage())
                            onClearSelection();
                    }}
                    onTap={(e) => {
                        if (e.target === e.target.getStage())
                            onClearSelection();
                    }}
                >
                    <Layer>
                        <PageCanvas
                            page={page}
                            pageWidth={pageWidth}
                            pageHeight={pageHeight}
                            photoUrls={photoUrls}
                            isBackCover={isBackCover}
                            isFrontCover={isFrontCover}
                            selectedSlotId={
                                selectedPageId === page.id
                                    ? selectedSlotId
                                    : null
                            }
                            selectedTextId={
                                selectedPageId === page.id
                                    ? selectedTextId
                                    : null
                            }
                            editingTextId={
                                selectedPageId === page.id
                                    ? editingTextId
                                    : null
                            }
                            editingCaption={editingCaption}
                            hideCaptions
                            hideCenterText
                            dragOverSlotId={
                                dragOverInfo?.pageId === page.id
                                    ? dragOverInfo.slotId
                                    : null
                            }
                            dragSourceSlotId={
                                dragSourceInfo?.pageId === page.id
                                    ? dragSourceInfo.slotId
                                    : null
                            }
                            onSlotClick={(slotId) =>
                                onSlotClick(page.id, slotId)
                            }
                        />
                    </Layer>
                </Stage>
                {/* Page-level drop zone / page drag handle */}
                <div
                    draggable={isInterior}
                    onClick={onClearSelection}
                    onDragStart={(e) => {
                        if (!isInterior) {
                            e.preventDefault();
                            return;
                        }
                        onPageDragStart(e, pageIndex);
                    }}
                    onDragOver={(e) => {
                        if (pageDragSourceRef.current !== null) {
                            onPageDragOverPage(e, pageIndex);
                        } else {
                            onPageDragOver(e, page.id);
                        }
                    }}
                    onDrop={(e) => {
                        if (pageDragSourceRef.current !== null) {
                            onPageDropOnPage(e, pageIndex);
                        } else {
                            onPageDrop(e, page.id);
                        }
                    }}
                    onDragEnd={() => {
                        onPageDragEndCleanup();
                        onPhotoDragEnd();
                    }}
                    style={{
                        position: "absolute",
                        inset: 0,
                        zIndex: 1,
                        cursor: isInterior ? "grab" : "default",
                        pointerEvents:
                            hasSelectedSlotOnPage &&
                            pageDragSource === null &&
                            !dragSourceInfo
                                ? "none"
                                : "auto",
                    }}
                />
                {/* Green overlay when page is a valid drop target for "add to page" */}
                {dragOverPageId === page.id &&
                    dragSourceInfo &&
                    dragSourceInfo.pageId !== page.id && (
                        <div
                            style={{
                                position: "absolute",
                                inset: 0,
                                zIndex: 3,
                                background: "rgba(8, 194, 37, 0.1)",
                                border: "2px dashed #08C225",
                                borderRadius: 2,
                                pointerEvents: "none",
                            }}
                        />
                    )}
                {/* Drag-and-drop overlay divs for photo slots.
            - Unselected + has photo: draggable=true for HTML5 rearrange.
            - Selected + has photo:   onMouseDown drives crop panning via
              document-level mousemove/mouseup listeners. Done in HTML (not
              Konva) because canvas + stacked overlay divs caused unreliable
              event delivery in Chromium/Linux. */}
                {page.slots.map((slot) => {
                    const isSelected =
                        selectedPageId === page.id &&
                        selectedSlotId === slot.id;
                    const canPanCrop =
                        isSelected && !!slot.photoId && !dragSourceInfo;
                    return (
                        <div
                            key={slot.id}
                            tabIndex={-1}
                            draggable={!!slot.photoId && !isSelected}
                            onDragStart={(e) => {
                                if (slot.photoId) {
                                    e.stopPropagation();
                                    onPhotoDragStart(
                                        e,
                                        page.id,
                                        slot.id,
                                        slot.photoId,
                                    );
                                } else {
                                    e.preventDefault();
                                }
                            }}
                            onDragOver={(e) =>
                                onSlotDragOver(e, page.id, slot.id)
                            }
                            onDrop={(e) => onPhotoDrop(e, page.id, slot.id)}
                            onDragEnd={onPhotoDragEnd}
                            onClick={(event) => {
                                event.currentTarget.focus({
                                    preventScroll: true,
                                });
                                onSlotClick(page.id, slot.id);
                            }}
                            onMouseDown={
                                canPanCrop
                                    ? (e) => {
                                          if (e.button !== 0) return;
                                          const photo = photos.find(
                                              (p) => p.id === slot.photoId,
                                          );
                                          if (!photo) return;
                                          e.preventDefault();
                                          e.stopPropagation();
                                          const startX = e.clientX;
                                          const startY = e.clientY;
                                          const origCropX = slot.cropX;
                                          const origCropY = slot.cropY;
                                          const sw =
                                              (slot.width / 100) * pageWidth;
                                          const sh =
                                              (slot.height / 100) * pageHeight;
                                          const imgAspect =
                                              photo.width / photo.height;
                                          const slotAspect = sw / sh;
                                          let drawW: number, drawH: number;
                                          if (imgAspect > slotAspect) {
                                              drawH = sh * slot.cropZoom;
                                              drawW = drawH * imgAspect;
                                          } else {
                                              drawW = sw * slot.cropZoom;
                                              drawH = drawW / imgAspect;
                                          }
                                          // slack is <= 0 (image is larger than slot in the
                                          // panned axis). If 0, no panning possible on that axis.
                                          const slackX = sw - drawW;
                                          const slackY = sh - drawH;
                                          const onMove = (ev: MouseEvent) => {
                                              const dx = ev.clientX - startX;
                                              const dy = ev.clientY - startY;
                                              const newCropX =
                                                  slackX !== 0
                                                      ? Math.max(
                                                            0,
                                                            Math.min(
                                                                1,
                                                                origCropX +
                                                                    dx / slackX,
                                                            ),
                                                        )
                                                      : origCropX;
                                              const newCropY =
                                                  slackY !== 0
                                                      ? Math.max(
                                                            0,
                                                            Math.min(
                                                                1,
                                                                origCropY +
                                                                    dy / slackY,
                                                            ),
                                                        )
                                                      : origCropY;
                                              if (
                                                  newCropX !== slot.cropX ||
                                                  newCropY !== slot.cropY
                                              ) {
                                                  updateSlot(page.id, slot.id, {
                                                      cropX: newCropX,
                                                      cropY: newCropY,
                                                  });
                                              }
                                          };
                                          const onUp = () => {
                                              document.removeEventListener(
                                                  "mousemove",
                                                  onMove,
                                              );
                                              document.removeEventListener(
                                                  "mouseup",
                                                  onUp,
                                              );
                                          };
                                          document.addEventListener(
                                              "mousemove",
                                              onMove,
                                          );
                                          document.addEventListener(
                                              "mouseup",
                                              onUp,
                                          );
                                      }
                                    : undefined
                            }
                            style={{
                                position: "absolute",
                                left: (slot.x / 100) * pageWidth,
                                top: (slot.y / 100) * pageHeight,
                                width: (slot.width / 100) * pageWidth,
                                height: (slot.height / 100) * pageHeight,
                                cursor: slot.photoId
                                    ? isSelected
                                        ? "move"
                                        : "grab"
                                    : "default",
                                pointerEvents:
                                    pageDragSource !== null ? "none" : "auto",
                                zIndex: 2,
                            }}
                        />
                    );
                })}
                {/* Text block interaction overlays — higher z-index than slots so text gets click priority */}
                {page.textBlocks.map((block) => {
                    const isTextEditing =
                        selectedPageId === page.id &&
                        editingTextId === block.id;
                    if (isTextEditing) return null;
                    const isTextSelected =
                        selectedPageId === page.id &&
                        selectedTextId === block.id;
                    const layout = getTextBlockLayout(block);
                    const bx = (layout.x / 100) * pageWidth;
                    const by = (layout.y / 100) * pageHeight;
                    const bw = (layout.width / 100) * pageWidth;
                    const bh = (layout.height / 100) * pageHeight;
                    const rotation = layout.rotation;
                    return (
                        <div
                            key={`text-overlay-${block.id}`}
                            onClick={(e) => {
                                e.stopPropagation();
                                onTextClick(page.id, block.id);
                            }}
                            onDoubleClick={(e) => {
                                e.stopPropagation();
                                onTextDblClick(page.id, block.id);
                            }}
                            onMouseDown={
                                isTextSelected
                                    ? (e) => {
                                          e.stopPropagation();
                                          e.preventDefault();
                                          const startX = e.clientX;
                                          const startY = e.clientY;
                                          const origX = layout.x;
                                          const origY = layout.y;
                                          const onMove = (ev: MouseEvent) => {
                                              const dx =
                                                  ((ev.clientX - startX) /
                                                      pageWidth) *
                                                  100;
                                              const dy =
                                                  ((ev.clientY - startY) /
                                                      pageHeight) *
                                                  100;
                                              onTextUpdate(page.id, block.id, {
                                                  x: origX + dx,
                                                  y: origY + dy,
                                              });
                                          };
                                          const onUp = () => {
                                              document.removeEventListener(
                                                  "mousemove",
                                                  onMove,
                                              );
                                              document.removeEventListener(
                                                  "mouseup",
                                                  onUp,
                                              );
                                          };
                                          document.addEventListener(
                                              "mousemove",
                                              onMove,
                                          );
                                          document.addEventListener(
                                              "mouseup",
                                              onUp,
                                          );
                                      }
                                    : undefined
                            }
                            style={{
                                position: "absolute",
                                left: bx - 4,
                                top: by - 4,
                                width: bw + 8,
                                height: bh + 8,
                                zIndex: 6,
                                cursor: isTextSelected ? "grab" : "pointer",
                                transform: rotation
                                    ? `rotate(${rotation}deg)`
                                    : undefined,
                                transformOrigin: "top left",
                                pointerEvents: dragSourceInfo ? "none" : "auto",
                            }}
                        />
                    );
                })}
                {/* Photo slot controls (zoom/delete) on selected slots */}
                {page.slots.map((slot) => {
                    const isSelected =
                        selectedPageId === page.id &&
                        selectedSlotId === slot.id;
                    if (!isSelected || !slot.photoId) return null;
                    return (
                        <SlotControls
                            key={`ctrl-${slot.id}`}
                            pageId={page.id}
                            slotId={slot.id}
                            slot={slot}
                            pageWidth={pageWidth}
                            pageHeight={pageHeight}
                        />
                    );
                })}
                {/* Inline text editing overlay */}
                {selectedPageId === page.id &&
                    editingTextId &&
                    (() => {
                        const block = page.textBlocks.find(
                            (t) => t.id === editingTextId,
                        );
                        if (!block) return null;
                        const value =
                            textDraft?.id === block.id
                                ? textDraft.value
                                : block.text;
                        const layout = getTextBlockLayout({
                            ...block,
                            text: value,
                        });
                        const bx = (layout.x / 100) * pageWidth;
                        const by = (layout.y / 100) * pageHeight;
                        const bw = (layout.width / 100) * pageWidth;
                        const fontSize = pageHeight * (layout.fontSize / 100);
                        const color = block.color ?? "#555555";
                        const rotation = block.rotation ?? 0;
                        return (
                            <input
                                key={`edit-${block.id}`}
                                type="text"
                                autoFocus
                                value={value}
                                onChange={(e) =>
                                    setTextDraft({
                                        id: block.id,
                                        value: e.target.value,
                                    })
                                }
                                placeholder="Type here"
                                onBlur={(e) => {
                                    onTextUpdate(page.id, block.id, {
                                        text: e.currentTarget.value,
                                    });
                                    onTextEditEnd();
                                }}
                                onKeyDown={(e) => {
                                    if (e.key === "Escape") {
                                        onTextUpdate(page.id, block.id, {
                                            text: e.currentTarget.value,
                                        });
                                        onTextEditEnd();
                                    }
                                    if (e.key === "Enter") {
                                        onTextUpdate(page.id, block.id, {
                                            text: e.currentTarget.value,
                                        });
                                        onTextEditEnd();
                                    }
                                }}
                                style={{
                                    position: "absolute",
                                    left: bx,
                                    top: by,
                                    transform: rotation
                                        ? `rotate(${rotation}deg)`
                                        : undefined,
                                    transformOrigin: "top left",
                                    width: bw,
                                    boxSizing: "border-box",
                                    zIndex: 15,
                                    border: "none",
                                    borderBottom:
                                        "1.5px solid rgba(8, 194, 37, 0.5)",
                                    outline: "none",
                                    borderRadius: 4,
                                    background: "rgba(255,255,255,0.85)",
                                    fontFamily: "var(--font-inter), sans-serif",
                                    fontSize: fontSize,
                                    fontWeight: 700,
                                    color: color,
                                    textAlign: "left" as const,
                                    padding: `0 ${(layout.padding / 100) * pageWidth}px`,
                                    lineHeight: TEXT_LINE_HEIGHT,
                                    caretColor: "#08C225",
                                }}
                            />
                        );
                    })()}
                {/* Floating text toolbar */}
                {selectedPageId === page.id &&
                    selectedTextId &&
                    !editingTextId &&
                    (() => {
                        const block = page.textBlocks.find(
                            (t) => t.id === selectedTextId,
                        );
                        if (!block) return null;
                        return (
                            <TextToolbar
                                block={getTextBlockLayout(block)}
                                pageWidth={pageWidth}
                                pageHeight={pageHeight}
                                onUpdate={(updates) =>
                                    onTextUpdate(page.id, block.id, updates)
                                }
                                onDelete={() => onTextDelete(page.id, block.id)}
                                onEdit={() => onTextDblClick(page.id, block.id)}
                            />
                        );
                    })()}
                {/* Empty pages offer a centered text area instead of photo captions. */}
                {photoCount === 0 &&
                    (page.centerText ||
                        (!isBackCover && page.textBlocks.length === 0)) &&
                    (() => {
                        const value = editingCenterText
                            ? centerTextDraft
                            : (page.centerText ?? "");
                        const layout = getCenterTextLayout({
                            ...page,
                            centerText: value,
                        });
                        if (!layout) return null;
                        const style: React.CSSProperties = {
                            position: "absolute",
                            left: (layout.x / 100) * pageWidth,
                            top: (layout.y / 100) * pageHeight,
                            width: (layout.width / 100) * pageWidth,
                            height: (layout.height / 100) * pageHeight,
                            boxSizing: "border-box",
                            zIndex: 4,
                            padding: `0 ${(layout.padding / 100) * pageWidth}px`,
                            border: "none",
                            background: "transparent",
                            fontFamily: "var(--font-outfit), sans-serif",
                            fontSize: (layout.fontSize / 100) * pageHeight,
                            fontWeight: CENTER_TEXT_FONT_WEIGHT,
                            lineHeight: layout.lineHeight,
                            textAlign: "center",
                            color: page.centerText ? "#2a2a2a" : "#aaa",
                            pointerEvents:
                                dragSourceInfo || pageDragSource !== null
                                    ? "none"
                                    : "auto",
                        };
                        return editingCenterText ? (
                            <textarea
                                autoFocus
                                aria-label="Page text"
                                placeholder="Add text..."
                                value={value}
                                wrap="soft"
                                onChange={(event) =>
                                    setCenterTextDraft(event.target.value)
                                }
                                onBlur={(event) => {
                                    if (
                                        event.currentTarget.value !==
                                        (page.centerText ?? "")
                                    ) {
                                        updatePage(page.id, {
                                            centerText:
                                                event.currentTarget.value,
                                        });
                                    }
                                    setEditingCenterText(false);
                                }}
                                onKeyDown={(event) => {
                                    if (
                                        !event.nativeEvent.isComposing &&
                                        (event.key === "Escape" ||
                                            (event.key === "Enter" &&
                                                (event.metaKey ||
                                                    event.ctrlKey)))
                                    ) {
                                        event.preventDefault();
                                        event.currentTarget.blur();
                                    }
                                }}
                                style={{
                                    ...style,
                                    color: "#2a2a2a",
                                    outline: "none",
                                    resize: "none",
                                    overflow: "hidden",
                                    whiteSpace: "pre-wrap",
                                    overflowWrap: "anywhere",
                                }}
                            />
                        ) : (
                            <button
                                type="button"
                                aria-label={
                                    page.centerText
                                        ? "Edit page text"
                                        : "Add text..."
                                }
                                onClick={(event) => {
                                    event.stopPropagation();
                                    onClearSelection();
                                    setCenterTextDraft(page.centerText ?? "");
                                    setEditingCenterText(true);
                                }}
                                style={{
                                    ...style,
                                    cursor: "text",
                                    whiteSpace: "pre",
                                    overflow: "hidden",
                                }}
                            >
                                {layout.lines.join("\n")}
                            </button>
                        );
                    })()}
                {showEmptyPageAddPhotos && (
                    <Button
                        type="button"
                        aria-label={`Add photos to page ${pageIndex}`}
                        startIcon={<AddPhotosIcon />}
                        disabled={processingPhotos}
                        disableRipple
                        onClick={(event) => {
                            event.stopPropagation();
                            onClearSelection();
                            onAddPhotos(page.id);
                        }}
                        sx={{
                            position: "absolute",
                            left: "50%",
                            bottom: Math.max(16, pageHeight * 0.07),
                            transform: "translateX(-50%)",
                            zIndex: 4,
                            minWidth: 0,
                            maxWidth: "calc(100% - 24px)",
                            height: 36,
                            px: "14px",
                            borderRadius: "999px",
                            bgcolor: "#F1F3F2",
                            color: "#59635D",
                            fontFamily: "var(--font-inter), sans-serif",
                            fontSize: 13,
                            fontWeight: 500,
                            textTransform: "none",
                            whiteSpace: "nowrap",
                            boxShadow: "none",
                            pointerEvents:
                                dragSourceInfo || pageDragSource !== null
                                    ? "none"
                                    : "auto",
                            transition:
                                "background-color 120ms ease, color 120ms ease",
                            "& .MuiButton-startIcon": { ml: 0, mr: "6px" },
                            "& .MuiSvgIcon-root": { fontSize: 17 },
                            "&:hover": { bgcolor: "#E4F1E7", color: "#246B37" },
                            "&:focus-visible": {
                                bgcolor: "#E4F1E7",
                                color: "#246B37",
                                outline: "2px solid #08C225",
                                outlineOffset: 2,
                            },
                        }}
                    >
                        Add photos
                    </Button>
                )}
                {/* Caption editing uses the same safe rectangles as the canvas and export. */}
                {(["top", "bottom"] as const).map((position) => {
                    if (position === "bottom" && isBackCover) return null;
                    const key =
                        position === "top" ? "topCaption" : "bottomCaption";
                    const isEditing = editingCaption === position;
                    const captionPage = isEditing
                        ? { ...page, [key]: captionValue }
                        : page;
                    const layout = getCaptionLayout(
                        captionPage,
                        position,
                        isFrontCover,
                    );
                    if (!layout) return null;
                    const style: React.CSSProperties = {
                        position: "absolute",
                        left: (layout.x / 100) * pageWidth,
                        top: (layout.y / 100) * pageHeight,
                        width: (layout.width / 100) * pageWidth,
                        height: (layout.height / 100) * pageHeight,
                        fontFamily: isFrontCover
                            ? "var(--font-outfit), sans-serif"
                            : "var(--font-inter), sans-serif",
                        fontSize: (layout.fontSize / 100) * pageHeight,
                        fontWeight: isFrontCover
                            ? CENTER_TEXT_FONT_WEIGHT
                            : CAPTION_FONT_WEIGHT,
                        lineHeight: TEXT_LINE_HEIGHT,
                        color: "#2a2a2a",
                        textAlign: "center",
                        boxSizing: "border-box",
                    };
                    return isEditing ? (
                        <input
                            key={position}
                            ref={captionInputRef}
                            value={captionValue}
                            onChange={(e) => setCaptionValue(e.target.value)}
                            onBlur={handleCaptionSave}
                            onKeyDown={(e) => {
                                if (e.key === "Enter") handleCaptionSave();
                                if (e.key === "Escape") handleCaptionCancel();
                            }}
                            style={{
                                ...style,
                                zIndex: 5,
                                border: "none",
                                outline: "none",
                                background: "white",
                                padding: 0,
                            }}
                        />
                    ) : (
                        <div
                            key={position}
                            onClick={(e) => {
                                e.stopPropagation();
                                handleCaptionClick(position);
                            }}
                            style={{
                                ...style,
                                zIndex: 4,
                                cursor: "text",
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "center",
                                overflow: "hidden",
                                whiteSpace: "nowrap",
                                pointerEvents: dragSourceInfo ? "none" : "auto",
                            }}
                        >
                            <span
                                style={{
                                    color: page[key] ? "#2a2a2a" : "#aaa",
                                    pointerEvents: "none",
                                }}
                            >
                                {page[key] ||
                                    (isFrontCover
                                        ? "Add title..."
                                        : "Add caption...")}
                            </span>
                        </div>
                    );
                })}
            </Box>
            <Typography
                sx={{
                    fontSize: { xs: 12, sm: 14 },
                    lineHeight: { xs: "16px", sm: "18px" },
                    color: uiColors.muted,
                    fontWeight: 600,
                    textAlign: "center",
                    mt: 0.5,
                }}
            >
                {pageIndex === 0
                    ? "Cover"
                    : pageIndex === totalPages - 1
                      ? "Back cover"
                      : pageIndex}
            </Typography>
        </Box>
    );

    const slotThumbnails = page.slots
        .filter((s) => s.photoId !== null)
        .map((s) => thumbnailUrls.get(s.photoId!) ?? "");

    const showPicker = photoCount > 0 && !hideLayoutPicker;
    const pickerContainer = (
        <Box
            sx={{
                width: PICKER_WIDTH,
                height: pageHeight,
                flexShrink: 0,
                display: "flex",
                flexDirection: "column",
                alignItems: pickerSide === "left" ? "flex-end" : "flex-start",
                ...(pickerSide === "left" ? { pr: 1 } : { pl: 1 }),
                gap: 1,
            }}
        >
            {showPicker && (
                <Box
                    className={styles.hoverControl}
                    sx={{
                        minHeight: 0,
                        overflowY: "auto",
                        p: "2px",
                        m: "-2px",
                    }}
                >
                    <LayoutPicker
                        photoCount={photoCount}
                        currentVariant={page.layoutVariant}
                        thumbnailUrls={slotThumbnails}
                        onSelect={(key) => setPageLayout(page.id, key)}
                        isFrontCover={isFrontCover}
                    />
                </Box>
            )}
            <PageMenu
                key={page.id}
                pageId={page.id}
                pageIndex={pageIndex}
                totalPages={totalPages}
                side={pickerSide}
                photoCount={photoCount}
                requiredBlank={isRequiredBlankPage(book.pages, page.id)}
                onAddPhotos={() => onAddPhotos(page.id)}
                onInsert={(position) => onInsertPage(pageIndex, position)}
                onDelete={() => {
                    onClearSelection();
                    removePage(page.id);
                }}
            />
        </Box>
    );

    return (
        <Box
            className={styles.page}
            sx={{ display: "flex", flexDirection: "row", alignItems: "start" }}
        >
            {pickerSide === "left" && pickerContainer}
            {pageBlock}
            {pickerSide === "right" && pickerContainer}
        </Box>
    );
}
