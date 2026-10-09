import { Box } from "@mui/material";
import React from "react";
import { minimumPostPhotoFrameAspectRatio } from "styles/tiles";

const gap = 8;

interface PostGridItem {
    id: string;
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

    const columnCount = fullWidth ? 1 : 2;
    const columnWidth = (width - (columnCount - 1) * gap) / columnCount;
    const columnHeights = new Array<number>(columnCount).fill(0);
    const tiles =
        width > gap
            ? items.map((item, index) => {
                  const column =
                      fullWidth || columnHeights[0]! <= columnHeights[1]!
                          ? 0
                          : 1;
                  const top = columnHeights[column]!;
                  const photoAspectRatio =
                      item.frameAspectRatio ??
                      (item.width && item.height
                          ? item.width / item.height
                          : 1);
                  const aspectRatio = fullWidth
                      ? Math.max(
                            minimumPostPhotoFrameAspectRatio,
                            photoAspectRatio,
                        )
                      : photoAspectRatio;
                  const height = columnWidth / aspectRatio;
                  columnHeights[column] = top + height + gap;
                  return (
                      <Box
                          key={item.id}
                          sx={{
                              height,
                              left: column * (columnWidth + gap),
                              position: "absolute",
                              top,
                              width: columnWidth,
                          }}
                      >
                          {renderTile(item, index)}
                      </Box>
                  );
              })
            : [];

    return (
        <Box
            ref={gridRef}
            sx={{
                height:
                    Math.max(0, ...columnHeights) - (tiles.length ? gap : 0),
                position: "relative",
                width: "100%",
            }}
        >
            {tiles}
        </Box>
    );
};
