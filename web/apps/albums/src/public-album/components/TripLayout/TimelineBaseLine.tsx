import { Box, styled } from "@mui/material";
import { memo } from "react";

interface TimelineBaseLineProps {
    locationPositions: { top: number; center: number }[];
}

export const TimelineBaseLine = memo<TimelineBaseLineProps>(
    ({ locationPositions }) => {
        const timelineContainer = document.querySelector("#timeline-container");
        if (!timelineContainer || locationPositions.length === 0) {
            return null;
        }

        const locationElements =
            timelineContainer.querySelectorAll(".timeline-location");
        if (locationElements.length === 0) {
            return null;
        }

        const lastLocation = locationElements[
            locationElements.length - 1
        ] as HTMLElement;
        const lastLocationRect = lastLocation.getBoundingClientRect();
        const heightToLastDot =
            lastLocation.offsetTop + lastLocationRect.height / 2;

        const firstLocationCenter = locationPositions[0]?.center || 0;

        return (
            <SolidLine
                sx={{
                    top: `${firstLocationCenter}px`,
                    height: `${heightToLastDot - firstLocationCenter}px`,
                }}
            />
        );
    },
);

const BaseLine = styled(Box)(() => ({
    position: "absolute",
    left: "50%",
    transform: "translateX(-1.5px)",
    width: "3px",
    zIndex: 0,
}));

const SolidLine = styled(BaseLine)(({ theme }) => ({
    backgroundColor: theme.palette.grey[300],
}));
