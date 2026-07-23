import AddIcon from "@mui/icons-material/Add";
import ArrowForwardIcon from "@mui/icons-material/ArrowForward";
import CloseIcon from "@mui/icons-material/Close";
import DoneIcon from "@mui/icons-material/Done";
import RemoveIcon from "@mui/icons-material/Remove";
import SearchIcon from "@mui/icons-material/Search";
import {
    Box,
    Button,
    CircularProgress,
    ClickAwayListener,
    Dialog,
    IconButton,
    InputBase,
    Stack,
    styled,
    Typography,
} from "@mui/material";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { haveWindow } from "ente-base/env";
import type { Location } from "ente-base/types";
import type { EnteFile } from "ente-media/file";
import { fileLocation } from "ente-media/file-metadata";
import { t } from "i18next";
import React, { useEffect, useMemo, useRef, useState } from "react";

import "leaflet-defaulticon-compatibility/dist/leaflet-defaulticon-compatibility.webpack.css";
import "leaflet/dist/leaflet.css";
// eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-unused-expressions
haveWindow() && require("leaflet-defaulticon-compatibility");
const leaflet = haveWindow()
    ? // eslint-disable-next-line @typescript-eslint/no-require-imports
      (require("leaflet") as typeof import("leaflet"))
    : null;

export interface EditLocationDialogProps extends ModalVisibilityProps {
    /**
     * The files whose location we want to edit.
     */
    files: EnteFile[];
    /**
     * Called when the user confirms the location update.
     *
     * @param location The new location to set for all selected files.
     * @returns A promise that resolves when the update is complete.
     */
    onConfirm: (location: Location) => Promise<void>;
}

/**
 * A full-screen dialog with an interactive map where users can drop a pin to
 * set the location for one or more photos.
 */
export const EditLocationDialog: React.FC<EditLocationDialogProps> = ({
    open,
    onClose,
    files,
    onConfirm,
}) => {
    const fullScreen = useIsSmallWidth();
    const [selectedLocation, setSelectedLocation] = useState<
        Location | undefined
    >(undefined);
    const [isLoading, setIsLoading] = useState(false);
    const [isSuccess, setIsSuccess] = useState(false);

    // Get initial location only if a single file is selected
    const initialLocation = useMemo(() => {
        if (files.length !== 1) return undefined;
        const file = files[0];
        return file ? fileLocation(file) : undefined;
    }, [files]);

    // Capture whether we're adding (vs editing) when dialog opens
    const [isAddingLocation, setIsAddingLocation] = useState(false);

    // Reset selected location and states only when dialog opens
    const prevOpenRef = useRef(false);
    useEffect(() => {
        if (open && !prevOpenRef.current) {
            setSelectedLocation(initialLocation);
            setIsLoading(false);
            setIsSuccess(false);
            // Determine add vs edit based on whether any file has location at open time
            setIsAddingLocation(!files.some((file) => fileLocation(file)));
        }
        prevOpenRef.current = open;
    }, [open, initialLocation, files]);

    const hasLocationChanged = useMemo(() => {
        if (!selectedLocation) return false;
        if (!initialLocation) return true;
        return (
            selectedLocation.latitude !== initialLocation.latitude ||
            selectedLocation.longitude !== initialLocation.longitude
        );
    }, [selectedLocation, initialLocation]);

    // Reset success state when user selects a new location
    const prevSelectedLocationRef = useRef(selectedLocation);
    useEffect(() => {
        const prevLoc = prevSelectedLocationRef.current;
        const currLoc = selectedLocation;
        const locationChanged =
            prevLoc?.latitude !== currLoc?.latitude ||
            prevLoc?.longitude !== currLoc?.longitude;

        if (isSuccess && locationChanged) {
            setIsSuccess(false);
        }
        prevSelectedLocationRef.current = selectedLocation;
    }, [isSuccess, selectedLocation]);

    const handleConfirm = async () => {
        if (selectedLocation && hasLocationChanged && !isLoading) {
            setIsLoading(true);
            setIsSuccess(false);
            try {
                await onConfirm(selectedLocation);
                setIsSuccess(true);
            } finally {
                setIsLoading(false);
            }
        }
    };

    useEffect(() => {
        if (!open || !isSuccess) return;
        const timeoutId = setTimeout(() => {
            onClose();
        }, 1000);
        return () => clearTimeout(timeoutId);
    }, [open, isSuccess, onClose]);

    return (
        <Dialog
            {...{ open, onClose, fullScreen }}
            maxWidth={false}
            slotProps={{
                paper: {
                    sx: !fullScreen
                        ? {
                              width: "min(900px, calc(100vw - 64px))",
                              height: "min(700px, calc(100vh - 64px))",
                          }
                        : undefined,
                },
            }}
        >
            <Stack sx={{ height: "100%", width: "100%" }}>
                <TitleBar
                    onClose={onClose}
                    onConfirm={handleConfirm}
                    canConfirm={hasLocationChanged}
                    isLoading={isLoading}
                    isSuccess={isSuccess}
                    isAddingLocation={isAddingLocation}
                />
                <Box sx={{ flex: 1, position: "relative" }}>
                    <EditableMap
                        open={open}
                        initialLocation={initialLocation}
                        selectedLocation={selectedLocation}
                        onLocationSelect={setSelectedLocation}
                    />
                </Box>
            </Stack>
        </Dialog>
    );
};

interface TitleBarProps {
    onClose: () => void;
    onConfirm: () => void;
    canConfirm: boolean;
    isLoading: boolean;
    isSuccess: boolean;
    isAddingLocation: boolean;
}

const TitleBar: React.FC<TitleBarProps> = ({
    onClose,
    onConfirm,
    canConfirm,
    isLoading,
    isSuccess,
    isAddingLocation,
}) => (
    <Stack
        direction="row"
        sx={{
            alignItems: "center",
            gap: 1,
            p: 1,
            borderBottom: "1px solid",
            borderColor: "divider",
        }}
    >
        <IconButton onClick={onClose} aria-label={t("close")} color="secondary">
            <CloseIcon />
        </IconButton>
        <Typography variant="h6" sx={{ flex: 1 }}>
            {t(isAddingLocation ? "add_location" : "edit_location")}
        </Typography>
        {isLoading ? (
            <Box
                sx={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    px: 2,
                }}
            >
                <CircularProgress size={24} />
            </Box>
        ) : isSuccess ? (
            <Box
                sx={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    px: 2,
                    color: "success.main",
                }}
            >
                <DoneIcon />
            </Box>
        ) : (
            <Button
                onClick={onConfirm}
                disabled={!canConfirm}
                variant="contained"
                color="accent"
            >
                {t("save_location")}
            </Button>
        )}
    </Stack>
);

interface EditableMapProps {
    open: boolean;
    initialLocation: Location | undefined;
    selectedLocation: Location | undefined;
    onLocationSelect: (location: Location) => void;
}

interface NominatimResult {
    place_id: number;
    display_name: string;
    lat: string;
    lon: string;
}

const EditableMap: React.FC<EditableMapProps> = ({
    open,
    initialLocation,
    selectedLocation,
    onLocationSelect,
}) => {
    const mapContainerRef = useRef<HTMLDivElement>(null);
    const mapRef = useRef<L.Map | null>(null);
    const markerRef = useRef<L.Marker | null>(null);
    const prevOpenRef = useRef(open);
    // Capture initial location at mount time to avoid map reset on file updates
    const initialLocationRef = useRef(initialLocation);

    // Search state
    const [searchQuery, setSearchQuery] = useState("");
    const [searchResults, setSearchResults] = useState<NominatimResult[]>([]);
    const [showResults, setShowResults] = useState(false);
    const [isSearching, setIsSearching] = useState(false);
    const searchInputRef = useRef<HTMLInputElement>(null);
    const searchRequestIdRef = useRef(0);
    const searchAbortRef = useRef<AbortController | null>(null);

    // Manual coordinate input state
    const [manualLat, setManualLat] = useState<string | null>(null);
    const [manualLon, setManualLon] = useState<string | null>(null);

    // Reset manual inputs when dialog opens or selectedLocation changes
    useEffect(() => {
        setManualLat(null);
        setManualLon(null);
    }, [open, selectedLocation]);

    const handleSearchChange = (query: string) => {
        setSearchQuery(query);
        if (searchAbortRef.current) {
            searchAbortRef.current.abort();
            searchAbortRef.current = null;
        }
        setIsSearching(false);
        setSearchResults([]);
        setShowResults(false);
    };

    const handleSearchSubmit = async (
        e?: React.SubmitEvent<HTMLFormElement> | React.MouseEvent,
    ) => {
        e?.preventDefault();

        const query =
            searchInputRef.current?.value.trim() ?? searchQuery.trim();
        if (query.length < 3 || isSearching) {
            if (query.length < 3) {
                setSearchResults([]);
                setShowResults(false);
            }
            return;
        }

        setSearchQuery(query);

        if (searchAbortRef.current) {
            searchAbortRef.current.abort();
        }

        const requestId = searchRequestIdRef.current + 1;
        searchRequestIdRef.current = requestId;
        const abortController = new AbortController();
        searchAbortRef.current = abortController;
        setIsSearching(true);

        try {
            await new Promise((resolve) => setTimeout(resolve, 750));
            if (
                searchRequestIdRef.current !== requestId ||
                abortController.signal.aborted
            ) {
                return;
            }

            const response = await fetch(
                `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(query)}&limit=5`,
                {
                    headers: { "Accept-Language": "en" },
                    signal: abortController.signal,
                },
            );
            const data = (await response.json()) as NominatimResult[];
            if (searchRequestIdRef.current !== requestId) return;
            setSearchResults(data);
            setShowResults(data.length > 0);
        } catch (error) {
            if (abortController.signal.aborted) return;
            if (searchRequestIdRef.current !== requestId) return;
            console.error("Search failed:", error);
            setSearchResults([]);
            setShowResults(false);
        } finally {
            if (searchRequestIdRef.current === requestId) {
                setIsSearching(false);
            }
        }
    };

    const handleSelectResult = (result: NominatimResult) => {
        const lat = parseFloat(result.lat);
        const lng = parseFloat(result.lon);
        onLocationSelect({ latitude: lat, longitude: lng });

        // Update map view
        if (mapRef.current) {
            mapRef.current.setView([lat, lng], 12);

            // Update or create marker
            if (markerRef.current) {
                markerRef.current.setLatLng([lat, lng]);
            } else if (leaflet) {
                const marker = leaflet
                    .marker([lat, lng], { draggable: true })
                    .addTo(mapRef.current);
                markerRef.current = marker;

                marker.on("dragend", () => {
                    const pos = marker.getLatLng();
                    onLocationSelect({ latitude: pos.lat, longitude: pos.lng });
                });
            }
        }

        setSearchQuery("");
        setSearchResults([]);
        setShowResults(false);
    };

    const handleManualCoordinates = () => {
        const latStr = manualLat ?? selectedLocation?.latitude.toFixed(6) ?? "";
        const lonStr =
            manualLon ?? selectedLocation?.longitude.toFixed(6) ?? "";
        const lat = parseFloat(latStr);
        const lon = parseFloat(lonStr);
        if (isNaN(lat) || isNaN(lon)) return;
        if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return;

        onLocationSelect({ latitude: lat, longitude: lon });

        if (mapRef.current) {
            mapRef.current.setView([lat, lon], 12);

            if (markerRef.current) {
                markerRef.current.setLatLng([lat, lon]);
            } else if (leaflet) {
                const marker = leaflet
                    .marker([lat, lon], { draggable: true })
                    .addTo(mapRef.current);
                markerRef.current = marker;

                marker.on("dragend", () => {
                    const pos = marker.getLatLng();
                    onLocationSelect({ latitude: pos.lat, longitude: pos.lng });
                });
            }
        }

        setManualLat(null);
        setManualLon(null);
    };

    const urlTemplate = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
    const attribution =
        '&copy; <a target="_blank" rel="noopener" href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';

    useEffect(() => {
        return () => {
            if (searchAbortRef.current) {
                searchAbortRef.current.abort();
            }
        };
    }, []);

    useEffect(() => {
        if (!open) return;
        const timeoutId = setTimeout(() => {
            searchInputRef.current?.focus();
        }, 0);
        return () => clearTimeout(timeoutId);
    }, [open]);

    useEffect(() => {
        const mapContainer = mapContainerRef.current;
        if (!mapContainer || !leaflet) return;

        // Don't recreate map if it already exists
        if (mapRef.current) return;

        // Use the captured initial location from mount time
        const initLoc = initialLocationRef.current;
        const initialLat = initLoc?.latitude;
        const initialLng = initLoc?.longitude;

        // Determine initial view
        const defaultCenter: L.LatLngTuple = [20, 0]; // World view
        const defaultZoom = 2;

        const hasInitialLocation =
            initialLat !== undefined && initialLng !== undefined;
        const center: L.LatLngTuple = hasInitialLocation
            ? [initialLat, initialLng]
            : defaultCenter;
        const zoom = hasInitialLocation ? 6 : defaultZoom;

        // Create map with zoom control disabled (we add custom controls)
        const map = leaflet
            .map(mapContainer, { zoomControl: false })
            .setView(center, zoom);
        leaflet.tileLayer(urlTemplate, { attribution }).addTo(map);
        mapRef.current = map;

        // Add initial marker if location exists
        if (hasInitialLocation) {
            const marker = leaflet
                .marker([initialLat, initialLng], { draggable: true })
                .addTo(map);
            markerRef.current = marker;

            marker.on("dragend", () => {
                const pos = marker.getLatLng();
                onLocationSelect({ latitude: pos.lat, longitude: pos.lng });
            });
        }

        // Handle map clicks to place/move marker
        map.on("click", (e: L.LeafletMouseEvent) => {
            const { lat, lng } = e.latlng;
            onLocationSelect({ latitude: lat, longitude: lng });

            if (markerRef.current) {
                markerRef.current.setLatLng([lat, lng]);
            } else {
                const marker = leaflet
                    .marker([lat, lng], { draggable: true })
                    .addTo(map);
                markerRef.current = marker;

                marker.on("dragend", () => {
                    const pos = marker.getLatLng();
                    onLocationSelect({ latitude: pos.lat, longitude: pos.lng });
                });
            }
        });

        return () => {
            if (mapRef.current) {
                mapRef.current.remove();
                mapRef.current = null;
                markerRef.current = null;
            }
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    // Sync marker when selection changes; recenter only when the dialog opens.
    useEffect(() => {
        const wasOpen = prevOpenRef.current;
        prevOpenRef.current = open;
        if (!open || !mapRef.current || !leaflet) return;
        const didOpen = !wasOpen;
        const nextLocation = selectedLocation ?? initialLocation;
        if (!nextLocation) return;
        const position: L.LatLngTuple = [
            nextLocation.latitude,
            nextLocation.longitude,
        ];

        if (markerRef.current) {
            markerRef.current.setLatLng(position);
        } else {
            const marker = leaflet
                .marker(position, { draggable: true })
                .addTo(mapRef.current);
            markerRef.current = marker;

            marker.on("dragend", () => {
                const pos = marker.getLatLng();
                onLocationSelect({ latitude: pos.lat, longitude: pos.lng });
            });
        }
        if (didOpen) {
            mapRef.current.setView(position, mapRef.current.getZoom());
        }
    }, [open, initialLocation, selectedLocation, onLocationSelect]);

    const handleZoomIn = (e: React.MouseEvent) => {
        e.stopPropagation();
        mapRef.current?.zoomIn();
    };
    const handleZoomOut = (e: React.MouseEvent) => {
        e.stopPropagation();
        mapRef.current?.zoomOut();
    };

    return (
        <MapWrapper>
            <MapContainer ref={mapContainerRef} />
            <SearchContainer>
                <ClickAwayListener onClickAway={() => setShowResults(false)}>
                    <Box
                        component="form"
                        onSubmit={handleSearchSubmit}
                        sx={{ position: "relative", width: "100%" }}
                    >
                        <SearchInputWrapper>
                            <InputBase
                                placeholder={t("search_location")}
                                value={searchQuery}
                                onChange={(e) =>
                                    handleSearchChange(e.target.value)
                                }
                                onFocus={() =>
                                    searchResults.length > 0 &&
                                    setShowResults(true)
                                }
                                inputRef={searchInputRef}
                                sx={{ flex: 1 }}
                                inputProps={{
                                    style: { padding: 0, paddingLeft: 8 },
                                }}
                            />
                            <IconButton
                                type="submit"
                                size="small"
                                disabled={
                                    isSearching || searchQuery.trim().length < 3
                                }
                                aria-label={t("search_location")}
                                sx={(theme) => ({
                                    ml: 1,
                                    p: 0,
                                    width: 32,
                                    height: 32,
                                    backgroundColor:
                                        theme.vars.palette.fill.faint,
                                    color: theme.vars.palette.text.base,
                                    transition:
                                        "background-color 0.2s ease, transform 0.2s ease",
                                    "&:hover": {
                                        backgroundColor:
                                            theme.vars.palette.fill.faintHover,
                                    },
                                    "&:active": {
                                        backgroundColor:
                                            theme.vars.palette.fill.faintHover,
                                        transform: "scale(0.96)",
                                    },
                                    "&.Mui-disabled": {
                                        backgroundColor:
                                            theme.vars.palette.background
                                                .elevatedPaper,
                                        color: theme.vars.palette.text.faint,
                                    },
                                })}
                            >
                                {isSearching ? (
                                    <CircularProgress
                                        size={18}
                                        thickness={5}
                                        sx={{
                                            display: "block",
                                            color: "inherit",
                                        }}
                                    />
                                ) : (
                                    <SearchIcon
                                        sx={{ color: "inherit", fontSize: 20 }}
                                    />
                                )}
                            </IconButton>
                        </SearchInputWrapper>
                        {showResults && (
                            <SearchResultsList>
                                {searchResults.map((result) => (
                                    <SearchResultItem
                                        key={result.place_id}
                                        onClick={() =>
                                            handleSelectResult(result)
                                        }
                                    >
                                        <Typography
                                            variant="body"
                                            sx={{
                                                overflow: "hidden",
                                                textOverflow: "ellipsis",
                                                whiteSpace: "nowrap",
                                            }}
                                        >
                                            {result.display_name}
                                        </Typography>
                                    </SearchResultItem>
                                ))}
                            </SearchResultsList>
                        )}
                    </Box>
                </ClickAwayListener>
            </SearchContainer>
            <CoordinateControls>
                <CoordinateInputWrapper>
                    <CoordinateInput
                        placeholder="Lat"
                        value={
                            manualLat ??
                            selectedLocation?.latitude.toFixed(6) ??
                            ""
                        }
                        onChange={(e) => setManualLat(e.target.value)}
                        type="number"
                        inputProps={{ step: "any" }}
                    />
                </CoordinateInputWrapper>
                <CoordinateInputWrapper>
                    <CoordinateInput
                        placeholder="Lon"
                        value={
                            manualLon ??
                            selectedLocation?.longitude.toFixed(6) ??
                            ""
                        }
                        onChange={(e) => setManualLon(e.target.value)}
                        type="number"
                        inputProps={{ step: "any" }}
                    />
                </CoordinateInputWrapper>
                <GoToLocationButton
                    onClick={handleManualCoordinates}
                    disabled={
                        manualLat === null &&
                        manualLon === null &&
                        !selectedLocation
                    }
                >
                    <ArrowForwardIcon sx={{ fontSize: 16 }} />
                </GoToLocationButton>
            </CoordinateControls>
            <ZoomControls>
                <ZoomButton onClick={handleZoomIn} aria-label={t("zoom_in")}>
                    <AddIcon />
                </ZoomButton>
                <ZoomButton onClick={handleZoomOut} aria-label={t("zoom_out")}>
                    <RemoveIcon />
                </ZoomButton>
            </ZoomControls>
        </MapWrapper>
    );
};

const MapWrapper = styled("div")({
    height: "100%",
    width: "100%",
    position: "relative",
});

const MapContainer = styled("div")({ height: "100%", width: "100%" });

const CoordinateControls = styled("div")(({ theme }) => ({
    position: "absolute",
    bottom: theme.spacing(2),
    left: theme.spacing(2),
    zIndex: 1000,
    display: "flex",
    alignItems: "center",
    gap: theme.spacing(1),
}));

const CoordinateInputWrapper = styled("div")(({ theme }) => ({
    display: "flex",
    alignItems: "center",
    backgroundColor: theme.vars.palette.background.paper,
    padding: theme.spacing(1, 1.5),
    borderRadius: "9999px",
    boxShadow: theme.shadows[4],
}));

const CoordinateInput = styled(InputBase)(({ theme }) => ({
    "& input": {
        width: 82,
        padding: 0,
        fontSize: "0.875rem",
        textAlign: "left",
        "&::placeholder": { color: theme.vars.palette.text.muted, opacity: 1 },
        "&::-webkit-outer-spin-button, &::-webkit-inner-spin-button": {
            WebkitAppearance: "none",
            margin: 0,
        },
        MozAppearance: "textfield",
    },
}));

const GoToLocationButton = styled(IconButton)(({ theme }) => ({
    backgroundColor: theme.vars.palette.background.paper,
    color: theme.vars.palette.text.base,
    width: 36,
    height: 36,
    boxShadow: theme.shadows[4],
    "&:hover": { backgroundColor: theme.vars.palette.background.elevatedPaper },
    "&.Mui-disabled": {
        backgroundColor: theme.vars.palette.background.elevatedPaper,
        color: theme.vars.palette.text.faint,
    },
}));

const ZoomControls = styled(Stack)(({ theme }) => ({
    position: "absolute",
    right: theme.spacing(3),
    bottom: theme.spacing(5),
    zIndex: 1000,
    gap: theme.spacing(1),
}));

const ZoomButton = styled(IconButton)(({ theme }) => ({
    backgroundColor: theme.vars.palette.background.paper,
    boxShadow: theme.shadows[4],
    width: 32,
    height: 32,
    borderRadius: 12,
    transition: "transform 0.2s ease-out",
    "&:hover": {
        backgroundColor: theme.vars.palette.background.paper,
        transform: "scale(1.05)",
    },
}));

const SearchContainer = styled("div")(({ theme }) => ({
    position: "absolute",
    top: theme.spacing(2),
    left: theme.spacing(2),
    right: theme.spacing(2),
    zIndex: 1001,
    display: "flex",
    justifyContent: "center",
}));

const SearchInputWrapper = styled("div")(({ theme }) => ({
    display: "inline-flex",
    alignItems: "center",
    width: "min(100%, 360px)",
    backgroundColor: theme.vars.palette.background.paper,
    padding: theme.spacing(1),
    borderRadius: "9999px",
    boxShadow: theme.shadows[4],
}));

const SearchResultsList = styled("div")(({ theme }) => ({
    position: "absolute",
    top: "100%",
    left: 0,
    right: 0,
    maxWidth: 280,
    marginTop: theme.spacing(1),
    backgroundColor: theme.vars.palette.background.paper,
    borderRadius: theme.spacing(1),
    overflow: "hidden",
    maxHeight: 250,
    overflowY: "auto",
    boxShadow: theme.shadows[4],
}));

const SearchResultItem = styled("div")(({ theme }) => ({
    padding: theme.spacing(1.5, 2),
    cursor: "pointer",
    "&:hover": { backgroundColor: theme.vars.palette.action.hover },
    "&:not(:last-child)": {
        borderBottom: `1px solid ${theme.vars.palette.divider}`,
    },
}));
