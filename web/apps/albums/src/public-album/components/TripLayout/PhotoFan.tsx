import { Box, styled } from "@mui/material";
import { memo } from "react";
import type { JourneyPoint } from "./types";

interface PhotoFanProps {
    cluster: JourneyPoint[];
    onPhotoClick?: (cluster: JourneyPoint[], fileId: number) => void;
}

export const PhotoFan = memo<PhotoFanProps>(({ cluster, onPhotoClick }) => {
    if (cluster.length === 0) {
        return null;
    }

    return (
        <PhotoFanContainer>
            {cluster.length >= 3 && (
                <>
                    {cluster[1] && (
                        <PhotoFrameLeft
                            onClick={() =>
                                cluster[1] &&
                                onPhotoClick?.(cluster, cluster[1].fileId)
                            }
                        >
                            <BackgroundLoadingBox />
                            <ImageWrapper
                                sx={{ transform: "skewY(8deg) scale(1.1)" }}
                            >
                                {cluster[1].image &&
                                    cluster[1].image.trim() !== "" && (
                                        <img
                                            src={cluster[1].image}
                                            alt={cluster[1].name}
                                            style={{
                                                position: "absolute",
                                                inset: 0,
                                                width: "100%",
                                                height: "100%",
                                                objectFit: "cover",
                                                zIndex: 1,
                                            }}
                                        />
                                    )}
                            </ImageWrapper>
                        </PhotoFrameLeft>
                    )}
                    {cluster[2] && (
                        <PhotoFrameRight
                            onClick={() =>
                                cluster[2] &&
                                onPhotoClick?.(cluster, cluster[2].fileId)
                            }
                        >
                            <BackgroundLoadingBox />
                            <ImageWrapper
                                sx={{ transform: "skewY(-8deg) scale(1.1)" }}
                            >
                                {cluster[2].image &&
                                    cluster[2].image.trim() !== "" && (
                                        <img
                                            src={cluster[2].image}
                                            alt={cluster[2].name}
                                            style={{
                                                position: "absolute",
                                                inset: 0,
                                                width: "100%",
                                                height: "100%",
                                                objectFit: "cover",
                                                zIndex: 1,
                                            }}
                                        />
                                    )}
                            </ImageWrapper>
                        </PhotoFrameRight>
                    )}
                </>
            )}

            {cluster[0] && (
                <MainPhotoFrame
                    onClick={() =>
                        cluster[0] && onPhotoClick?.(cluster, cluster[0].fileId)
                    }
                >
                    {cluster[0].image && cluster[0].image.trim() !== "" ? (
                        <img
                            src={cluster[0].image}
                            alt={cluster[0].name}
                            style={{
                                position: "absolute",
                                inset: 0,
                                width: "100%",
                                height: "100%",
                                objectFit: "cover",
                            }}
                        />
                    ) : (
                        <LoadingBox />
                    )}

                    {cluster.length === 2 && <CountBadge>+1</CountBadge>}
                    {cluster.length > 3 && (
                        <CountBadge>+{cluster.length - 3}</CountBadge>
                    )}
                </MainPhotoFrame>
            )}
        </PhotoFanContainer>
    );
});

const PhotoFanContainer = styled(Box)(({ theme }) => ({
    position: "relative",
    width: "180px",
    height: "240px",
    [theme.breakpoints.up("md")]: {
        transition: "transform 0.3s ease-in-out",
        cursor: "pointer",
        "&:hover": { transform: "scale(1.05)" },
    },
}));

const PhotoFrame = styled(Box)(() => ({
    position: "absolute",
    border: "2px solid white",
    zIndex: 10,
    width: "180px",
    height: "207px",
    borderRadius: "14px",
    overflow: "hidden",
    cursor: "pointer",
}));

const PhotoFrameLeft = styled(PhotoFrame)({
    transform: "translateX(-33px) skewY(-8deg)",
    top: "16.5px",
    left: "0",
});

const PhotoFrameRight = styled(PhotoFrame)({
    transform: "translateX(33px) skewY(8deg)",
    top: "16.5px",
    left: "0",
});

const MainPhotoFrame = styled(Box)(() => ({
    position: "relative",
    width: "100%",
    height: "100%",
    border: "2px solid white",
    zIndex: 20,
    borderRadius: "14px",
    overflow: "hidden",
    cursor: "pointer",
}));

const ImageWrapper = styled(Box)({
    position: "relative",
    width: "100%",
    height: "100%",
});

const CountBadge = styled(Box)({
    position: "absolute",
    top: "6px",
    right: "6px",
    background: "white",
    color: "black",
    borderRadius: "6px",
    padding: "4px 6px",
    minHeight: "20px",
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    fontSize: "11px",
    fontWeight: "600",
    boxShadow: "0 1px 3px rgba(0,0,0,0.3)",
});

const LoadingBox = styled(Box)({
    width: "100%",
    height: "100%",
    borderRadius: "12px",
    animation: "skeleton-pulse 1.5s ease-in-out infinite",
    "@keyframes skeleton-pulse": {
        "0%": { backgroundColor: "#ffffff" },
        "50%": { backgroundColor: "#f0f0f0" },
        "100%": { backgroundColor: "#ffffff" },
    },
});

const BackgroundLoadingBox = styled(Box)({
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    borderRadius: "12px",
    zIndex: 0,
    animation: "skeleton-pulse 1.5s ease-in-out infinite",
    "@keyframes skeleton-pulse": {
        "0%": { backgroundColor: "#ffffff" },
        "50%": { backgroundColor: "#f0f0f0" },
        "100%": { backgroundColor: "#ffffff" },
    },
});
