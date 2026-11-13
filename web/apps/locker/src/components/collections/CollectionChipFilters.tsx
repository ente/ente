import {
    lockerColors,
    lockerColorSx,
    lockerContentMaxWidth,
    lockerTextBodySx,
} from "@/styles/tokens";
import type { LockerCollection } from "@/types";
import ChevronLeftRoundedIcon from "@mui/icons-material/ChevronLeftRounded";
import ChevronRightRoundedIcon from "@mui/icons-material/ChevronRightRounded";
import { Box, ButtonBase, Stack, Typography } from "@mui/material";
import React, { useEffect, useRef, useState } from "react";

export const CollectionChipFilters: React.FC<{
    collections: LockerCollection[];
    selectedCollectionIDs: number[];
    onToggleCollection: (collectionID: number) => void;
}> = ({ collections, selectedCollectionIDs, onToggleCollection }) => {
    const scrollContainerRef = useRef<HTMLDivElement | null>(null);
    const [showLeftScrollHint, setShowLeftScrollHint] = useState(false);
    const [showRightScrollHint, setShowRightScrollHint] = useState(false);

    const scrollLeft = () => {
        const container = scrollContainerRef.current;
        if (!container) {
            return;
        }

        container.scrollBy({
            left: -Math.max(container.clientWidth * 0.6, 160),
            behavior: "smooth",
        });
    };

    const scrollRight = () => {
        const container = scrollContainerRef.current;
        if (!container) {
            return;
        }

        container.scrollBy({
            left: Math.max(container.clientWidth * 0.6, 160),
            behavior: "smooth",
        });
    };

    useEffect(() => {
        const container = scrollContainerRef.current;
        if (!container) {
            return;
        }

        const updateScrollHint = () => {
            setShowLeftScrollHint(container.scrollLeft > 8);
            const remainingScroll =
                container.scrollWidth -
                container.clientWidth -
                container.scrollLeft;
            setShowRightScrollHint(remainingScroll > 8);
        };

        updateScrollHint();
        container.addEventListener("scroll", updateScrollHint, {
            passive: true,
        });
        window.addEventListener("resize", updateScrollHint);

        return () => {
            container.removeEventListener("scroll", updateScrollHint);
            window.removeEventListener("resize", updateScrollHint);
        };
    }, [collections, selectedCollectionIDs]);

    return (
        <Box
            sx={{ width: "100%", maxWidth: lockerContentMaxWidth, mx: "auto" }}
        >
            <Stack direction="row" sx={{ alignItems: "stretch", gap: 0 }}>
                {showLeftScrollHint && (
                    <Box
                        sx={{
                            width: 28,
                            flexShrink: 0,
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                        }}
                    >
                        <ButtonBase
                            onClick={scrollLeft}
                            sx={(theme) => ({
                                width: 28,
                                height: "100%",
                                borderRadius: "999px",
                                ...lockerColorSx(theme, { color: "iconColor" }),
                            })}
                        >
                            <ChevronLeftRoundedIcon sx={{ fontSize: 28 }} />
                        </ButtonBase>
                    </Box>
                )}
                <Box sx={{ position: "relative", flex: 1, minWidth: 0 }}>
                    <Stack
                        ref={scrollContainerRef}
                        direction="row"
                        sx={{
                            gap: 1,
                            flexWrap: "nowrap",
                            overflowX: "auto",
                            overflowY: "hidden",
                            justifyContent: "flex-start",
                            pr: 2,
                            pb: 0.5,
                            scrollbarWidth: "none",
                            "&::-webkit-scrollbar": { display: "none" },
                        }}
                    >
                        {collections.map((collection) => {
                            const isSelected = selectedCollectionIDs.includes(
                                collection.id,
                            );

                            return (
                                <ButtonBase
                                    key={collection.id}
                                    onClick={() =>
                                        onToggleCollection(collection.id)
                                    }
                                    sx={(theme) => ({
                                        minHeight: 44,
                                        padding: "12px 20px",
                                        borderRadius: "16px",
                                        whiteSpace: "nowrap",
                                        flexShrink: 0,
                                        ...lockerColorSx(theme, {
                                            backgroundColor: isSelected
                                                ? "primary"
                                                : "fillLight",
                                            color: isSelected
                                                ? "specialWhite"
                                                : "textLight",
                                        }),
                                    })}
                                >
                                    <Typography
                                        variant="small"
                                        sx={lockerTextBodySx}
                                    >
                                        {collection.name}
                                    </Typography>
                                </ButtonBase>
                            );
                        })}
                    </Stack>
                    {showLeftScrollHint && (
                        <Box
                            sx={(theme) => ({
                                position: "absolute",
                                top: 0,
                                left: 0,
                                bottom: 0,
                                width: 40,
                                pointerEvents: "none",
                                background: `linear-gradient(90deg, ${lockerColors.backgroundBase.dark} 0%, ${lockerColors.backgroundBase.dark}00 100%)`,
                                ...theme.applyStyles("light", {
                                    background: `linear-gradient(90deg, ${lockerColors.backgroundBase.light} 0%, ${lockerColors.backgroundBase.light}00 100%)`,
                                }),
                            })}
                        />
                    )}
                    {showRightScrollHint && (
                        <Box
                            sx={(theme) => ({
                                position: "absolute",
                                top: 0,
                                right: 0,
                                bottom: 0,
                                width: 72,
                                pointerEvents: "none",
                                background: `linear-gradient(90deg, ${lockerColors.backgroundBase.dark}00 0%, ${lockerColors.backgroundBase.dark} 100%)`,
                                ...theme.applyStyles("light", {
                                    background: `linear-gradient(90deg, ${lockerColors.backgroundBase.light}00 0%, ${lockerColors.backgroundBase.light} 100%)`,
                                }),
                            })}
                        />
                    )}
                </Box>
                {showRightScrollHint && (
                    <Box
                        sx={{
                            width: 28,
                            flexShrink: 0,
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                        }}
                    >
                        <ButtonBase
                            onClick={scrollRight}
                            sx={(theme) => ({
                                width: 28,
                                height: "100%",
                                borderRadius: "999px",
                                ...lockerColorSx(theme, { color: "iconColor" }),
                            })}
                        >
                            <ChevronRightRoundedIcon sx={{ fontSize: 28 }} />
                        </ButtonBase>
                    </Box>
                )}
            </Stack>
        </Box>
    );
};
