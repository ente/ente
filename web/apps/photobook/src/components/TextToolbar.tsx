"use client";

import { popupShadow, uiColors } from "@/theme/colors";

import type { TextBlock } from "@/lib/types";
import React, { useEffect, useRef, useState } from "react";
import { CloseIcon, DeleteIcon, EditIcon, RotateIcon } from "./icons";

const PRESET_COLORS = [
    "#555555",
    "#ffffff",
    "#08C225",
    "#3B82F6",
    "#EF4444",
    "#F59E0B",
    "#8B5CF6",
    "#EC4899",
];

const FONT_SIZES = [
    { label: "S", value: 2 },
    { label: "M", value: 3 },
    { label: "L", value: 4.5 },
    { label: "XL", value: 6 },
];

interface TextToolbarProps {
    block: TextBlock;
    pageWidth: number;
    pageHeight: number;
    onUpdate: (updates: Partial<TextBlock>) => void;
    onDelete: () => void;
    onEdit: () => void;
}

export default function TextToolbar({
    block,
    pageWidth,
    pageHeight,
    onUpdate,
    onDelete,
    onEdit,
}: TextToolbarProps) {
    const [showColors, setShowColors] = useState(false);
    const [showRotation, setShowRotation] = useState(false);
    const colorRef = useRef<HTMLDivElement>(null);
    const rotationRef = useRef<HTMLDivElement>(null);

    // Close popups on outside click
    useEffect(() => {
        if (!showColors && !showRotation) return;
        const handler = (e: MouseEvent) => {
            if (
                showColors &&
                colorRef.current &&
                !colorRef.current.contains(e.target as Node)
            ) {
                setShowColors(false);
            }
            if (
                showRotation &&
                rotationRef.current &&
                !rotationRef.current.contains(e.target as Node)
            ) {
                setShowRotation(false);
            }
        };
        document.addEventListener("mousedown", handler);
        return () => document.removeEventListener("mousedown", handler);
    }, [showColors, showRotation]);

    const bx = (block.x / 100) * pageWidth;
    const by = (block.y / 100) * pageHeight;
    const bw = (block.width / 100) * pageWidth;

    // Position toolbar above the text block, centered
    const toolbarLeft = bx + bw / 2;
    const toolbarTop = by - 44;

    const currentSize = FONT_SIZES.find(
        (s) => Math.abs(s.value - (block.fontSize ?? 2.5)) < 0.3,
    );

    const btnStyle: React.CSSProperties = {
        width: 28,
        height: 28,
        border: "none",
        background: "transparent",
        color: uiColors.text,
        cursor: "pointer",
        borderRadius: 4,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        fontSize: 13,
        fontFamily: "var(--font-inter), sans-serif",
        padding: 0,
        transition: "background 0.15s",
    };

    const activeBtnStyle: React.CSSProperties = {
        ...btnStyle,
        background: uiColors.control,
        color: uiColors.text,
    };

    const handleSizeChange = () => {
        const currentIdx = FONT_SIZES.findIndex(
            (s) => Math.abs(s.value - (block.fontSize ?? 2.5)) < 0.3,
        );
        const nextIdx = (currentIdx + 1) % FONT_SIZES.length;
        onUpdate({
            fontSize: FONT_SIZES[nextIdx]!.value,
            style: FONT_SIZES[nextIdx]!.value >= 4 ? "title" : "body",
        });
    };

    const rotation = block.rotation ?? 0;

    return (
        <div
            style={{
                position: "absolute",
                left: toolbarLeft,
                top: toolbarTop,
                transform: "translateX(-50%)",
                zIndex: 20,
                display: "flex",
                alignItems: "center",
                gap: 2,
                background: uiColors.surface,
                backdropFilter: "blur(12px)",
                borderRadius: 8,
                padding: "3px 4px",
                boxShadow: popupShadow,
            }}
            onMouseDown={(e) => e.stopPropagation()}
        >
            {/* Edit text */}
            <button
                style={btnStyle}
                onClick={onEdit}
                onMouseEnter={(e) =>
                    (e.currentTarget.style.background = uiColors.background)
                }
                onMouseLeave={(e) =>
                    (e.currentTarget.style.background = "transparent")
                }
                title="Edit text"
            >
                <EditIcon sx={{ fontSize: 14 }} />
            </button>

            <div
                style={{ width: 1, height: 18, background: uiColors.border }}
            />

            {/* Font size cycle */}
            <button
                style={{
                    ...btnStyle,
                    fontWeight: 700,
                    fontSize: 12,
                    width: 32,
                }}
                onClick={handleSizeChange}
                onMouseEnter={(e) =>
                    (e.currentTarget.style.background = uiColors.background)
                }
                onMouseLeave={(e) =>
                    (e.currentTarget.style.background = "transparent")
                }
                title="Font size"
            >
                {currentSize?.label ?? "M"}
            </button>

            {/* Color */}
            <div ref={colorRef} style={{ position: "relative" }}>
                <button
                    style={btnStyle}
                    onClick={() => {
                        setShowColors(!showColors);
                        setShowRotation(false);
                    }}
                    onMouseEnter={(e) =>
                        (e.currentTarget.style.background = uiColors.background)
                    }
                    onMouseLeave={(e) =>
                        (e.currentTarget.style.background = "transparent")
                    }
                    title="Text color"
                >
                    <div
                        style={{
                            width: 16,
                            height: 16,
                            borderRadius: 3,
                            background: block.color ?? "#555555",
                            border: `2px solid ${uiColors.border}`,
                        }}
                    />
                </button>
                {showColors && (
                    <div
                        style={{
                            position: "absolute",
                            top: "calc(100% + 6px)",
                            left: "50%",
                            transform: "translateX(-50%)",
                            background: uiColors.surface,
                            backdropFilter: "blur(12px)",
                            borderRadius: 8,
                            padding: 6,
                            display: "grid",
                            gridTemplateColumns: "repeat(4, 1fr)",
                            gap: 4,
                            boxShadow: popupShadow,
                        }}
                    >
                        {PRESET_COLORS.map((c) => (
                            <button
                                key={c}
                                onClick={() => {
                                    onUpdate({ color: c });
                                    setShowColors(false);
                                }}
                                style={{
                                    width: 24,
                                    height: 24,
                                    borderRadius: 4,
                                    background: c,
                                    border:
                                        (block.color ?? "#555555") === c
                                            ? "2px solid #08C225"
                                            : c === "#ffffff"
                                              ? `1px solid ${uiColors.muted}`
                                              : `1px solid ${uiColors.border}`,
                                    cursor: "pointer",
                                    padding: 0,
                                }}
                            />
                        ))}
                    </div>
                )}
            </div>

            {/* Rotation */}
            <div ref={rotationRef} style={{ position: "relative" }}>
                <button
                    style={rotation !== 0 ? activeBtnStyle : btnStyle}
                    onClick={() => {
                        setShowRotation(!showRotation);
                        setShowColors(false);
                    }}
                    onMouseEnter={(e) => {
                        if (rotation === 0)
                            e.currentTarget.style.background =
                                uiColors.background;
                    }}
                    onMouseLeave={(e) => {
                        if (rotation === 0)
                            e.currentTarget.style.background = "transparent";
                    }}
                    title={`Rotate (${Math.round(rotation)}°)`}
                >
                    <RotateIcon sx={{ fontSize: 14 }} />
                </button>
                {showRotation && (
                    <div
                        style={{
                            position: "absolute",
                            top: "calc(100% + 6px)",
                            left: "50%",
                            transform: "translateX(-50%)",
                            background: uiColors.surface,
                            backdropFilter: "blur(12px)",
                            borderRadius: 8,
                            padding: "8px 12px",
                            boxShadow: popupShadow,
                            display: "flex",
                            alignItems: "center",
                            gap: 8,
                            whiteSpace: "nowrap",
                        }}
                    >
                        <input
                            type="range"
                            min={-180}
                            max={180}
                            step={1}
                            value={rotation}
                            onChange={(e) =>
                                onUpdate({ rotation: Number(e.target.value) })
                            }
                            style={{
                                width: 120,
                                accentColor: "#08C225",
                                cursor: "pointer",
                            }}
                        />
                        <span
                            style={{
                                color: uiColors.muted,
                                fontSize: 11,
                                fontFamily: "var(--font-inter), sans-serif",
                                minWidth: 32,
                                textAlign: "right",
                            }}
                        >
                            {Math.round(rotation)}°
                        </span>
                        {rotation !== 0 && (
                            <button
                                onClick={() => onUpdate({ rotation: 0 })}
                                style={{
                                    ...btnStyle,
                                    width: 20,
                                    height: 20,
                                    fontSize: 11,
                                    color: uiColors.muted,
                                }}
                                onMouseEnter={(e) =>
                                    (e.currentTarget.style.background =
                                        uiColors.background)
                                }
                                onMouseLeave={(e) =>
                                    (e.currentTarget.style.background =
                                        "transparent")
                                }
                                title="Reset rotation"
                            >
                                <CloseIcon sx={{ fontSize: 12 }} />
                            </button>
                        )}
                    </div>
                )}
            </div>

            <div
                style={{ width: 1, height: 18, background: uiColors.border }}
            />

            {/* Delete */}
            <button
                style={{ ...btnStyle, color: uiColors.danger }}
                onClick={onDelete}
                onMouseEnter={(e) =>
                    (e.currentTarget.style.background = "rgba(255,80,80,0.15)")
                }
                onMouseLeave={(e) =>
                    (e.currentTarget.style.background = "transparent")
                }
                title="Delete text"
            >
                <DeleteIcon sx={{ fontSize: 14 }} />
            </button>
        </div>
    );
}
