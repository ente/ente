import { Box, Skeleton, styled, Typography } from "@mui/material";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { AlbumDescription } from "ente-new/photos/components/gallery/ListHeader";
import { memo } from "react";
import type { JourneyPoint } from "./types";

interface TripCoverProps {
    journeyData: JourneyPoint[];
    albumTitle?: string;
    albumDescription?: string;
    coverImageUrl?: string | null;
}

export const TripCover = memo<TripCoverProps>(
    ({ journeyData, albumTitle, albumDescription, coverImageUrl }) => {
        const sortedData = [...journeyData].sort(
            (a, b) => a.timestamp - b.timestamp,
        );
        const firstData = sortedData[0];
        const lastData = sortedData[sortedData.length - 1];
        if (!firstData || !lastData) {
            return null;
        }
        const firstDate = new Date(firstData.timestamp);
        const lastDate = new Date(lastData.timestamp);
        const diffTime = Math.abs(lastDate.getTime() - firstDate.getTime());
        const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
        const monthYear = firstDate.toLocaleDateString("en-US", {
            month: "long",
            year: "numeric",
        });

        const uniqueLocations = new Set(
            journeyData
                .filter((point) => point.name && point.country)
                .map((point) => `${point.name}, ${point.country}`),
        );
        const locationCount = uniqueLocations.size;

        return (
            <CoverContainer>
                <CoverImageContainer>
                    {coverImageUrl ? (
                        <>
                            <img
                                src={coverImageUrl}
                                alt="Trip Cover"
                                style={{
                                    position: "absolute",
                                    inset: 0,
                                    width: "100%",
                                    height: "100%",
                                    objectFit: "cover",
                                }}
                            />
                            <GradientOverlay />
                        </>
                    ) : (
                        <Skeleton
                            variant="rectangular"
                            width="100%"
                            height="100%"
                            sx={{ bgcolor: "#f5f5f5" }}
                        />
                    )}

                    <LogoContainer>
                        <EnteLogo height={20} />
                    </LogoContainer>

                    <ContentContainer>
                        {coverImageUrl ? (
                            <>
                                <TripTitle>{albumTitle || "Trip"}</TripTitle>
                                <TripSubtitle>
                                    {monthYear} • {diffDays} days •{" "}
                                    {locationCount} locations
                                </TripSubtitle>
                                <AlbumDescription
                                    description={albumDescription}
                                    sx={{
                                        maxWidth: "420px",
                                        mt: "4px",
                                        color: "rgba(255, 255, 255, 0.85)",
                                    }}
                                />
                            </>
                        ) : (
                            <>
                                <Skeleton
                                    variant="text"
                                    width="200px"
                                    height="40px"
                                    sx={{
                                        mb: "5px",
                                        bgcolor: "rgba(255,255,255,0.95)",
                                    }}
                                />
                                <Skeleton
                                    variant="text"
                                    width="270px"
                                    height="24px"
                                    sx={{ bgcolor: "rgba(255,255,255,0.7)" }}
                                />
                            </>
                        )}
                    </ContentContainer>
                </CoverImageContainer>
            </CoverContainer>
        );
    },
);

const CoverContainer = styled(Box)({ marginBottom: "48px" });

const CoverImageContainer = styled(Box)(({ theme }) => ({
    aspectRatio: "16/8",
    position: "relative",
    marginBottom: "12px",
    borderRadius: "24px",
    overflow: "hidden",
    backgroundColor: "#e0e0e0",
    [theme.breakpoints.down(1440)]: { aspectRatio: "16/6" },
}));

const GradientOverlay = styled(Box)({
    position: "absolute",
    inset: 0,
    background:
        "linear-gradient(to bottom, rgba(0,0,0,0.4), transparent 30%, transparent 70%, rgba(0,0,0,0.7))",
});

const LogoContainer = styled(Box)(() => ({
    position: "absolute",
    top: "20px",
    left: "20px",
    color: "white",
}));

const ContentContainer = styled(Box)({
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    padding: "24px",
    color: "white",
});

const TripTitle = styled(Typography)({
    fontSize: "30px",
    fontWeight: "bold",
    marginBottom: "10px",
    lineHeight: 1.2,
    component: "h1",
});

const TripSubtitle = styled(Typography)({
    color: "rgba(255, 255, 255, 0.8)",
    fontSize: "16px",
    fontWeight: "600",
    margin: "0",
});
