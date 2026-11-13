import { Box, Typography, styled } from "@mui/material";
import { memo } from "react";
import { PhotoFan } from "./PhotoFan";
import type { JourneyPoint } from "./types";

interface MobileTimelineLocationProps {
    cluster: JourneyPoint[];
    index: number;
    journeyData: JourneyPoint[];
    onRef: (el: HTMLDivElement | null) => void;
    onPhotoClick?: (cluster: JourneyPoint[], fileId: number) => void;
}

export const MobileTimelineLocation = memo<MobileTimelineLocationProps>(
    ({ cluster, index, journeyData, onRef, onPhotoClick }) => {
        const firstPhoto = cluster[0];
        if (!firstPhoto) return null;

        const sortedData = [...journeyData].sort(
            (a, b) => a.timestamp - b.timestamp,
        );
        const firstData = sortedData[0];
        if (!firstData) return null;
        const firstDate = new Date(firstData.timestamp);
        const photoDate = new Date(firstPhoto.timestamp);

        const firstDateOnly = new Date(
            firstDate.getFullYear(),
            firstDate.getMonth(),
            firstDate.getDate(),
        );
        const photoDateOnly = new Date(
            photoDate.getFullYear(),
            photoDate.getMonth(),
            photoDate.getDate(),
        );
        const diffTime = photoDateOnly.getTime() - firstDateOnly.getTime();
        const dayNumber = Math.floor(diffTime / (1000 * 60 * 60 * 24)) + 1;

        return (
            <MobileLocationContainer
                ref={onRef}
                id={`location-${index}`}
                className="timeline-location"
            >
                <CenteredPhotoContainer>
                    <PhotoFanWrapper>
                        <PhotoFan
                            cluster={cluster}
                            onPhotoClick={onPhotoClick}
                        />

                        <PhotoOverlay>
                            <DayBadge>
                                DAY {dayNumber} •{" "}
                                {new Date(firstPhoto.timestamp)
                                    .toLocaleDateString("en-US", {
                                        month: "short",
                                        day: "numeric",
                                    })
                                    .toUpperCase()}
                            </DayBadge>
                            <LocationTitle>
                                {firstPhoto.name && firstPhoto.name.length > 17
                                    ? firstPhoto.name.substring(0, 14) + "..."
                                    : firstPhoto.name}
                            </LocationTitle>
                            <LocationCountry>
                                {firstPhoto.country}
                            </LocationCountry>
                        </PhotoOverlay>
                    </PhotoFanWrapper>
                </CenteredPhotoContainer>
            </MobileLocationContainer>
        );
    },
);

const MobileLocationContainer = styled(Box)({
    position: "relative",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    width: "100%",
    height: "40svh",
    scrollSnapAlign: "start",
    scrollSnapStop: "always",
    padding: "0",
});

const CenteredPhotoContainer = styled(Box)({
    position: "relative",
    display: "flex",
    justifyContent: "center",
});

const PhotoFanWrapper = styled(Box)({
    position: "relative",
    width: "180px",
    height: "240px",
    transition: "transform 0.3s ease-in-out",
    cursor: "pointer",
    "&:hover": { transform: "scale(1.05)" },
});

const PhotoOverlay = styled(Box)({
    position: "absolute",
    bottom: "2px",
    left: "2px",
    right: "2px",
    zIndex: 30,
    pointerEvents: "none",
    background:
        "linear-gradient(to top, rgba(0, 0, 0, 0.8) 0%, rgba(0, 0, 0, 0.4) 60%, transparent 100%)",
    borderRadius: "0 0 12px 12px",
    padding: "16px",
    minHeight: "fit-content",
});

const DayBadge = styled(Box)({
    display: "inline-flex",
    alignItems: "center",
    backgroundColor: "transparent",
    border: "none",
    borderRadius: "0",
    padding: "0",
    marginBottom: "4px",
    fontSize: "10px",
    fontWeight: "600",
    color: "white",
    textTransform: "uppercase",
    letterSpacing: "0.15em",
    textShadow: "0 2px 8px rgba(0, 0, 0, 0.8)",
});

const LocationTitle = styled(Typography)(() => ({
    fontSize: "18px",
    fontWeight: "600",
    color: "white",
    margin: "0 0 2px 0",
    lineHeight: "1.2",
    textShadow: "0 2px 8px rgba(0, 0, 0, 0.5)",
    component: "h3",
}));

const LocationCountry = styled(Typography)(() => ({
    fontSize: "13px",
    color: "rgba(200, 200, 200, 0.9)",
    margin: "0",
    textShadow: "0 1px 4px rgba(0, 0, 0, 0.5)",
    component: "p",
}));
