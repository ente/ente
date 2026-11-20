import { Box, Skeleton, Stack } from "@mui/material";
import { computeThumbnailGridLayoutParams } from "ente-new/photos/components/utils/thumbnail-grid-layout";
import AutoSizer from "react-virtualized-auto-sizer";

export const GalleryLoadingSkeleton = ({
    backdrop = false,
}: {
    backdrop?: boolean;
}) => (
    <Box
        aria-hidden
        sx={(theme) => ({
            flex: 1,
            minHeight: 0,
            overflow: "hidden",
            "& .MuiSkeleton-root": {
                bgcolor: backdrop ? "fill.faint" : "fill.fainter",
                animation: backdrop ? "none" : undefined,
            },
            ...(backdrop
                ? {
                      position: "absolute",
                      inset: 0,
                      pointerEvents: "none",
                      opacity: 0.3,
                      maskImage: "linear-gradient(#000 10%, transparent 95%)",
                  }
                : theme.applyStyles("dark", {
                      "& .MuiSkeleton-root": { bgcolor: "fill.faint" },
                  })),
            "@media (prefers-reduced-motion: reduce)": {
                "& .MuiSkeleton-root": { animation: "none" },
            },
        })}
    >
        <AutoSizer>
            {({ width, height }) => {
                const { columns, itemHeight, paddingInline, gap } =
                    computeThumbnailGridLayoutParams(width);
                if (itemHeight <= 0) return null;
                const gridSx = {
                    display: "grid",
                    gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))`,
                    gap: `${gap}px`,
                };
                const thumbnails = (rows: number) =>
                    Array.from({ length: rows * columns }, (_, index) => (
                        <Skeleton
                            key={index}
                            variant="rounded"
                            height={itemHeight}
                        />
                    ));

                return (
                    <Box
                        sx={{
                            width,
                            boxSizing: "border-box",
                            px: `${paddingInline}px`,
                        }}
                    >
                        <Stack sx={{ height: 72, gap: "8px", pt: "4px" }}>
                            <Skeleton
                                variant="rounded"
                                width={104}
                                height={24}
                            />
                            <Skeleton
                                variant="rounded"
                                width={64}
                                height={14}
                            />
                        </Stack>
                        <Skeleton
                            variant="rounded"
                            width={88}
                            height={14}
                            sx={{ mb: "12px" }}
                        />
                        <Box sx={gridSx}>{thumbnails(1)}</Box>
                        <Skeleton
                            variant="rounded"
                            width={112}
                            height={14}
                            sx={{ mt: "20px", mb: "12px" }}
                        />
                        <Box sx={gridSx}>
                            {thumbnails(Math.ceil(height / (itemHeight + gap)))}
                        </Box>
                    </Box>
                );
            }}
        </AutoSizer>
    </Box>
);
