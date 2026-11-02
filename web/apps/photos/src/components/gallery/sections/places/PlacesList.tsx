import {
    Box,
    List,
    ListItem,
    ListItemButton,
    Stack,
    Typography,
    styled,
} from "@mui/material";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import log from "ente-base/log";
import type { EnteFile } from "ente-media/file";
import { ItemCard, PreviewItemTile } from "ente-new/photos/components/Tiles";
import { t } from "i18next";
import { useEffect, useRef, useState } from "react";
import { listPlaces } from "../../../../services/places";

export interface PlaceSelection {
    latitude: number;
    longitude: number;
}

export const PlacesList = ({
    files,
    searchQuery,
    selectedPlace,
    onSelectPlace,
}: {
    files: EnteFile[];
    searchQuery: string;
    selectedPlace?: PlaceSelection;
    onSelectPlace: (place: PlaceSelection | undefined) => void;
}) => {
    const listRef = useRef<HTMLUListElement>(null);
    const [result, setResult] = useState<{
        files: EnteFile[];
        groups?: Awaited<ReturnType<typeof listPlaces>>;
    }>();

    useEffect(() => {
        let cancelled = false;
        void listPlaces(files)
            .then((groups) => {
                if (!cancelled) setResult({ files, groups });
            })
            .catch((error: unknown) => {
                log.error("Failed to list places", error);
                if (!cancelled) setResult({ files });
            });
        return () => {
            cancelled = true;
        };
    }, [files]);

    useEffect(() => {
        if (listRef.current) listRef.current.scrollTop = 0;
    }, [searchQuery]);

    const currentResult = result?.files === files ? result : undefined;
    const query = searchQuery.trim().toLowerCase();
    const matchingGroups = currentResult?.groups?.filter(({ city }) =>
        `${city.name}, ${city.country}`.toLowerCase().includes(query),
    );

    return (
        <Stack sx={{ flex: 1, minHeight: 0, gap: "8px" }}>
            <ListItemButton
                selected={!selectedPlace}
                aria-current={!selectedPlace ? "true" : undefined}
                onClick={() => onSelectPlace(undefined)}
                sx={{
                    ...placeRowSx,
                    flexShrink: 0,
                    flexGrow: 0,
                    "&.Mui-selected": {
                        bgcolor: "var(--gallery-navigation-surface)",
                    },
                }}
            >
                <Box
                    component="img"
                    src="/images/places/your-map.png"
                    alt=""
                    sx={{
                        width: 36,
                        height: 36,
                        flexShrink: 0,
                        borderRadius: "12px",
                    }}
                />
                <Typography sx={placeNameSx}>{t("your_map")}</Typography>
            </ListItemButton>
            {!currentResult ? (
                <Stack role="status" aria-label={t("loading")} sx={{ p: 2 }}>
                    <ActivityIndicator />
                </Stack>
            ) : !currentResult.groups ? (
                <Typography role="alert">{t("generic_error_retry")}</Typography>
            ) : !matchingGroups?.length ? (
                <Typography role="status">{t("no_results")}</Typography>
            ) : (
                <List
                    ref={listRef}
                    disablePadding
                    aria-label={t("search_places")}
                    sx={{
                        flex: 1,
                        minHeight: 0,
                        overflow: "auto",
                        display: "flex",
                        flexDirection: "column",
                        gap: "8px",
                    }}
                >
                    {matchingGroups.map(({ city, coverFile }) => (
                        <ListItem
                            key={`${city.name}-${city.country}-${city.latitude}-${city.longitude}`}
                            disableGutters
                            title={`${city.name}, ${city.country}`}
                            disablePadding
                        >
                            <ListItemButton
                                selected={
                                    selectedPlace?.latitude === city.latitude &&
                                    selectedPlace.longitude === city.longitude
                                }
                                aria-current={
                                    selectedPlace?.latitude === city.latitude &&
                                    selectedPlace.longitude === city.longitude
                                        ? "true"
                                        : undefined
                                }
                                onClick={() =>
                                    onSelectPlace({
                                        latitude: city.latitude,
                                        longitude: city.longitude,
                                    })
                                }
                                sx={placeRowSx}
                            >
                                <Box aria-hidden sx={{ flexShrink: 0 }}>
                                    <ItemCard
                                        coverFile={coverFile}
                                        TileComponent={PlaceCover}
                                    />
                                </Box>
                                <Typography noWrap sx={placeNameSx}>
                                    {city.name}
                                </Typography>
                            </ListItemButton>
                        </ListItem>
                    ))}
                </List>
            )}
        </Stack>
    );
};

const placeRowSx = {
    height: 48,
    minHeight: 48,
    px: "12px",
    py: 0,
    gap: "12px",
    alignItems: "center",
    borderRadius: "12px",
};

const placeNameSx = {
    flex: 1,
    minWidth: 0,
    fontFamily: '"Inter Variable", Inter, sans-serif',
    fontSize: 14,
    fontWeight: 500,
    lineHeight: "20px",
};

const PlaceCover = styled(PreviewItemTile)({
    width: 36,
    height: 36,
    borderRadius: "12px",
    cursor: "inherit",
});
