import { Box } from "@mui/material";
import React from "react";
import { layoutPostGrid } from "utils/post-grid";

interface PostGridItem {
    id: string;
    batchIndex?: number;
    frameAspectRatio?: number;
    width?: number;
    height?: number;
}

export const SpacePostGrid = <Item extends PostGridItem>({
    items,
    postCount,
    renderTile,
}: {
    items: Item[];
    postCount?: number;
    renderTile: (item: Item, index: number) => React.ReactNode;
}) => {
    const [width, setWidth] = React.useState(0);
    const gridRef = React.useRef<HTMLDivElement | null>(null);

    React.useLayoutEffect(() => {
        const grid = gridRef.current!;
        const observer = new ResizeObserver(([entry]) =>
            setWidth(entry!.contentRect.width),
        );
        setWidth(grid.getBoundingClientRect().width);
        observer.observe(grid);
        return () => observer.disconnect();
    }, []);

    const fullWidth =
        postCount != undefined && Math.max(postCount, items.length) < 4;

    const { tiles, height } = layoutPostGrid(items, width, fullWidth);

    return (
        <Box ref={gridRef} sx={{ height, position: "relative", width: "100%" }}>
            {tiles.map((tile, index) => (
                <Box
                    key={items[index]!.id}
                    sx={{ ...tile, position: "absolute" }}
                >
                    {renderTile(items[index]!, index)}
                </Box>
            ))}
        </Box>
    );
};
