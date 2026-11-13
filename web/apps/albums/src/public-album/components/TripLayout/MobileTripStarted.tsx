import { Box, styled, Typography } from "@mui/material";
import { memo } from "react";
import type { JourneyPoint } from "./types";

interface MobileTripStartedProps {
    onRef: (el: HTMLDivElement | null) => void;
    journeyData: JourneyPoint[];
}

export const MobileTripStarted = memo<MobileTripStartedProps>(
    ({ onRef, journeyData }) => {
        const sortedData = [...journeyData].sort(
            (a, b) => a.timestamp - b.timestamp,
        );
        const firstPhoto = sortedData[0];
        const firstPhotoDate = firstPhoto
            ? new Date(firstPhoto.timestamp).toLocaleDateString("en-US", {
                  year: "numeric",
                  month: "long",
                  day: "numeric",
              })
            : "";

        return (
            <MobileTripStartedContainer ref={onRef}>
                <MobileTripStartedContent>
                    <MobileTripStartedText>
                        <TripStartedTitle>Trip started</TripStartedTitle>
                        {firstPhotoDate && (
                            <>
                                <br />
                                <TripStartedDate>
                                    {firstPhotoDate}
                                </TripStartedDate>
                            </>
                        )}
                    </MobileTripStartedText>
                </MobileTripStartedContent>
                <MobileTripStartedDot />
                <MobileTripStartedLine />
            </MobileTripStartedContainer>
        );
    },
);

const MobileTripStartedContainer = styled(Box)({
    position: "relative",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    height: "40svh",
    scrollSnapAlign: "start",
    scrollSnapStop: "always",
    padding: "0",
    overflow: "visible",
});

const MobileTripStartedContent = styled(Box)({
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    marginBottom: "20px",
});

const MobileTripStartedText = styled(Typography)(({ theme }) => ({
    fontSize: "16px",
    fontWeight: "500",
    color: theme.palette.text.secondary,
    textAlign: "center",
}));

const MobileTripStartedLine = styled(Box)(({ theme }) => ({
    position: "absolute",
    left: "50%",
    bottom: "-100px",
    height: "200px",
    width: "3px",
    backgroundColor: theme.palette.grey[300],
    transform: "translateX(-1.5px)",
    zIndex: 0,
}));

const TripStartedTitle = styled("span")(({ theme }) => ({
    fontSize: "14px",
    fontWeight: 500,
    color: theme.palette.text.primary,
}));

const TripStartedDate = styled("span")(({ theme }) => ({
    fontSize: "12px",
    fontWeight: "normal",
    color: theme.palette.text.secondary,
}));

const MobileTripStartedDot = styled(Box)(({ theme }) => ({
    width: "8px",
    height: "8px",
    backgroundColor: theme.palette.grey[500],
    borderRadius: "50%",
    margin: "10px auto 0 auto",
    position: "relative",
    zIndex: 1,
}));
