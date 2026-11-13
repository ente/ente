import { Box, Typography, styled } from "@mui/material";
import { memo } from "react";
import { PhotoFan } from "./PhotoFan";
import type { JourneyPoint } from "./types";

interface TimelineLocationProps {
    cluster: JourneyPoint[];
    index: number;
    photoClusters: JourneyPoint[][];
    scrollProgress: number;
    journeyData: JourneyPoint[];
    onRef: (el: HTMLDivElement | null) => void;
    onPhotoClick?: (cluster: JourneyPoint[], fileId: number) => void;
}

export const TimelineLocation = memo<TimelineLocationProps>(
    ({
        cluster,
        index,
        photoClusters,
        scrollProgress,
        journeyData,
        onRef,
        onPhotoClick,
    }) => {
        const isLeft = index % 2 === 0;
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

        const currentLocationIndex = Math.round(
            scrollProgress * Math.max(0, photoClusters.length - 1),
        );
        const isActive = index === currentLocationIndex;

        return (
            <LocationContainer
                ref={onRef}
                id={`location-${index}`}
                className="timeline-location"
                sx={{
                    marginBottom:
                        index === photoClusters.length - 1 ? "48px" : "96px",
                }}
            >
                <DotBackground />
                <TimelineDot isReached={isActive} />

                {isLeft ? (
                    <>
                        <LeftContent>
                            <DayBadge>
                                DAY {dayNumber} •{" "}
                                {new Date(firstPhoto.timestamp)
                                    .toLocaleDateString("en-US", {
                                        month: "long",
                                        day: "numeric",
                                    })
                                    .toUpperCase()}
                            </DayBadge>
                            <LocationTitle sx={{ textAlign: "right" }}>
                                {firstPhoto.name}
                            </LocationTitle>
                            <LocationCountry sx={{ textAlign: "right" }}>
                                {firstPhoto.country}
                            </LocationCountry>
                        </LeftContent>
                        <RightPhotoContainer
                            sx={{
                                paddingLeft:
                                    cluster.length >= 3 ? "72px" : "40px",
                            }}
                        >
                            <PhotoFan
                                cluster={cluster}
                                onPhotoClick={onPhotoClick}
                            />
                        </RightPhotoContainer>
                    </>
                ) : (
                    <>
                        <LeftPhotoContainer
                            sx={{
                                paddingRight:
                                    cluster.length >= 3 ? "72px" : "40px",
                            }}
                        >
                            <PhotoFan
                                cluster={cluster}
                                onPhotoClick={onPhotoClick}
                            />
                        </LeftPhotoContainer>
                        <RightContent>
                            <DayBadge>
                                DAY {dayNumber} •{" "}
                                {new Date(firstPhoto.timestamp)
                                    .toLocaleDateString("en-US", {
                                        month: "long",
                                        day: "numeric",
                                    })
                                    .toUpperCase()}
                            </DayBadge>
                            <LocationTitle sx={{ textAlign: "left" }}>
                                {firstPhoto.name}
                            </LocationTitle>
                            <LocationCountry sx={{ textAlign: "left" }}>
                                {firstPhoto.country}
                            </LocationCountry>
                        </RightContent>
                    </>
                )}
            </LocationContainer>
        );
    },
);

const LocationContainer = styled(Box)({
    position: "relative",
    display: "flex",
    alignItems: "center",
});

const DotBackground = styled(Box)(({ theme }) => ({
    position: "absolute",
    left: "50%",
    top: "50%",
    transform: "translate(-50%, -50%)",
    width: "24px",
    height: "40px",
    borderRadius: "50%",
    zIndex: 10,
    backgroundColor: theme.palette.background.paper,
}));

const TimelineDot = styled(Box, {
    shouldForwardProp: (prop) => prop !== "isReached",
})<{ isReached: boolean }>(({ theme, isReached }) => ({
    position: "absolute",
    left: "50%",
    top: "50%",
    transform: "translate(-50%, -50%)",
    borderRadius: "50%",
    border: `2px solid ${theme.palette.background.paper}`,
    zIndex: 20,
    width: "12px",
    height: "12px",
    transition: "all 0.3s",
    backgroundColor: isReached
        ? theme.palette.success.main
        : theme.palette.text.primary,
    boxShadow: isReached
        ? `0 0 0 3px ${theme.palette.success.main}30, 0 0 0 6px ${theme.palette.success.main}15`
        : "none",
}));

const ContentContainer = styled(Box)({ width: "50%", paddingTop: "58px" });

const LeftContent = styled(ContentContainer)({
    paddingRight: "32px",
    textAlign: "right",
});

const RightContent = styled(ContentContainer)({
    paddingLeft: "32px",
    textAlign: "left",
});

const PhotoContainer = styled(Box)({ width: "50%" });

const LeftPhotoContainer = styled(PhotoContainer)({
    display: "flex",
    justifyContent: "flex-end",
});

const RightPhotoContainer = styled(PhotoContainer)({});

const DayBadge = styled(Box)(({ theme }) => ({
    display: "inline-flex",
    alignItems: "center",
    border: `1px solid ${theme.palette.grey[300]}`,
    borderRadius: "8px",
    padding: "4px 12px",
    marginBottom: "10px",
    fontSize: "11px",
    fontWeight: "600",
    color: theme.palette.text.secondary,
    textTransform: "uppercase",
    letterSpacing: "0.15em",
}));

const LocationTitle = styled(Typography)(({ theme }) => ({
    fontSize: "20px",
    fontWeight: "600",
    color: theme.palette.text.primary,
    margin: "0",
    lineHeight: "1.2",
    component: "h3",
}));

const LocationCountry = styled(Typography)(({ theme }) => ({
    fontSize: "14px",
    color: theme.palette.text.secondary,
    margin: "4px 0 0 0",
    component: "p",
}));
