import AddIcon from "@mui/icons-material/Add";
import CloseIcon from "@mui/icons-material/Close";
import DoneIcon from "@mui/icons-material/Done";
import RemoveIcon from "@mui/icons-material/Remove";
import SearchIcon from "@mui/icons-material/Search";
import {
    Box,
    ButtonBase,
    CircularProgress,
    ClickAwayListener,
    Dialog,
    IconButton,
    InputBase,
    Stack,
    styled,
    Typography,
} from "@mui/material";
import { InlineErrorIndicator } from "ente-base/components/ErrorIndicator";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import {
    v2CancelButtonSx,
    v2CloseButtonSx,
    v2HeaderRowSx,
    v2HelperSx,
    v2InputSx,
    v2LabelSx,
    v2PaperSx,
    v2SubmitButtonSx,
    v2TitleSx,
} from "ente-base/components/SingleInput.styles";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { isSxArray } from "ente-base/components/utils/sx";
import log from "ente-base/log";
import type { Location } from "ente-base/types";
import {
    uploadSheetMediaQuery,
    uploadSheetPaperSx,
    useIsUploadSheet,
} from "ente-gallery/components/upload-progress/bottom-sheet";
import { getLeafletWithDefaultIcons } from "ente-gallery/utils/leaflet";
import type { EnteFile } from "ente-media/file";
import { fileLocation } from "ente-media/file-metadata";
import { t } from "i18next";
import React, {
    useCallback,
    useEffect,
    useId,
    useMemo,
    useRef,
    useState,
} from "react";
import { SlideUpTransition } from "./mui/SlideUpTransition";

import "leaflet-defaulticon-compatibility/dist/leaflet-defaulticon-compatibility.webpack.css";
import "leaflet/dist/leaflet.css";
const leaflet = getLeafletWithDefaultIcons();

export interface EditLocationDialogProps extends ModalVisibilityProps {
    files: EnteFile[];
    onConfirm: (location: Location) => Promise<void>;
}

export const EditLocationDialog: React.FC<EditLocationDialogProps> = ({
    open,
    onClose,
    files,
    onConfirm,
}) => {
    const isSheet = useIsUploadSheet();
    const titleID = useId();
    const [coordinateDraft, setCoordinateDraft] = useState<Location>();
    const [coordinatesValid, setCoordinatesValid] = useState(true);
    const onCoordinateDraftChange = useCallback(
        (location: Location | undefined, valid: boolean) => {
            setCoordinateDraft(location);
            setCoordinatesValid(valid);
        },
        [],
    );
    const [selectedLocation, setSelectedLocation] = useState<
        Location | undefined
    >(undefined);
    const [isLoading, setIsLoading] = useState(false);
    const [isSuccess, setIsSuccess] = useState(false);
    const [saveFailed, setSaveFailed] = useState(false);

    const initialLocation = useMemo(() => {
        if (files.length !== 1) return undefined;
        const file = files[0];
        return file ? fileLocation(file) : undefined;
    }, [files]);

    const [isAddingLocation, setIsAddingLocation] = useState(false);

    // File updates while open must not reset the user's edits.
    const prevOpenRef = useRef(false);
    useEffect(() => {
        if (open && !prevOpenRef.current) {
            setSelectedLocation(initialLocation);
            setCoordinateDraft(undefined);
            setCoordinatesValid(true);
            setIsLoading(false);
            setIsSuccess(false);
            setSaveFailed(false);
            setIsAddingLocation(!files.some((file) => fileLocation(file)));
        }
        prevOpenRef.current = open;
    }, [open, initialLocation, files]);

    const locationToSave = coordinateDraft ?? selectedLocation;
    const hasLocationChanged = useMemo(() => {
        if (!locationToSave || !coordinatesValid) return false;
        if (!initialLocation) return true;
        return (
            locationToSave.latitude !== initialLocation.latitude ||
            locationToSave.longitude !== initialLocation.longitude
        );
    }, [locationToSave, initialLocation, coordinatesValid]);

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
        if (locationToSave && hasLocationChanged && !isLoading) {
            setIsLoading(true);
            setIsSuccess(false);
            setSaveFailed(false);
            try {
                await onConfirm(locationToSave);
                setIsSuccess(true);
            } catch (error) {
                log.error("Failed to update photo location", error);
                setSaveFailed(true);
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

    const busy = isLoading || isSuccess;
    return (
        <Dialog
            open={open}
            onClose={busy ? undefined : onClose}
            maxWidth={false}
            aria-labelledby={titleID}
            slots={isSheet ? { transition: SlideUpTransition } : undefined}
            slotProps={{
                paper: {
                    sx: [
                        ...(isSxArray(v2PaperSx) ? v2PaperSx : [v2PaperSx]),
                        {
                            width: "min(560px, calc(100svw - 32px))",
                            maxWidth: 560,
                            boxSizing: "border-box",
                        },
                        uploadSheetPaperSx,
                    ],
                },
            }}
        >
            <Stack
                sx={{
                    p: "20px",
                    gap: "20px",
                    [uploadSheetMediaQuery]: {
                        pb: "calc(20px + env(safe-area-inset-bottom, 0px))",
                    },
                }}
                aria-busy={isLoading}
            >
                <Stack direction="row" sx={v2HeaderRowSx}>
                    <Typography component="h2" id={titleID} sx={v2TitleSx}>
                        {t(isAddingLocation ? "add_location" : "edit_location")}
                    </Typography>
                    <IconButton
                        onClick={onClose}
                        disabled={busy}
                        aria-label={t("close")}
                        sx={v2CloseButtonSx}
                    >
                        <CloseIcon sx={{ fontSize: 18 }} />
                    </IconButton>
                </Stack>
                <Box
                    sx={{ pointerEvents: busy ? "none" : undefined }}
                    inert={busy}
                >
                    <EditableMap
                        open={open}
                        initialLocation={initialLocation}
                        selectedLocation={selectedLocation}
                        onLocationSelect={setSelectedLocation}
                        onCoordinateDraftChange={onCoordinateDraftChange}
                    />
                </Box>
                {saveFailed && (
                    <Box role="alert">
                        <InlineErrorIndicator />
                    </Box>
                )}
                <Stack direction="row" sx={{ gap: "12px" }}>
                    <FocusVisibleButton
                        onClick={onClose}
                        disabled={busy}
                        sx={v2CancelButtonSx}
                    >
                        {t("cancel")}
                    </FocusVisibleButton>
                    <LoadingButton
                        onClick={handleConfirm}
                        aria-label={t("save_location")}
                        loading={isLoading}
                        disabled={!hasLocationChanged || isSuccess}
                        color="accent"
                        sx={v2SubmitButtonSx}
                    >
                        {isSuccess ? (
                            <DoneIcon aria-label={t("save_location")} />
                        ) : (
                            t("save_location")
                        )}
                    </LoadingButton>
                </Stack>
            </Stack>
        </Dialog>
    );
};

interface EditableMapProps {
    open: boolean;
    initialLocation: Location | undefined;
    selectedLocation: Location | undefined;
    onLocationSelect: (location: Location) => void;
    onCoordinateDraftChange: (
        location: Location | undefined,
        valid: boolean,
    ) => void;
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
    onCoordinateDraftChange,
}) => {
    const mapContainerRef = useRef<HTMLDivElement>(null);
    const mapRef = useRef<L.Map | null>(null);
    const markerRef = useRef<L.Marker | null>(null);
    const prevOpenRef = useRef(open);
    // File updates must not reset the map.
    const initialLocationRef = useRef(initialLocation);

    const [searchQuery, setSearchQuery] = useState("");
    const [searchResults, setSearchResults] = useState<NominatimResult[]>([]);
    const [showResults, setShowResults] = useState(false);
    const [isSearching, setIsSearching] = useState(false);
    const searchInputRef = useRef<HTMLInputElement>(null);
    const searchRequestIdRef = useRef(0);
    const searchAbortRef = useRef<AbortController | null>(null);
    const searchTimeoutRef = useRef<ReturnType<typeof setTimeout> | undefined>(
        undefined,
    );

    const latitudeID = useId();
    const longitudeID = useId();
    const coordinateErrorID = useId();
    const [coordinateError, setCoordinateError] = useState(false);
    const [manualLat, setManualLat] = useState<string | null>(null);
    const [manualLon, setManualLon] = useState<string | null>(null);

    useEffect(() => {
        setManualLat(null);
        setManualLon(null);
        setCoordinateError(false);
        onCoordinateDraftChange(undefined, true);
    }, [open, selectedLocation, onCoordinateDraftChange]);

    const searchLocations = useCallback(async (query: string) => {
        if (query.length < 3) return;
        searchAbortRef.current?.abort();
        const requestId = ++searchRequestIdRef.current;
        const abortController = new AbortController();
        searchAbortRef.current = abortController;
        setIsSearching(true);
        try {
            const response = await fetch(
                `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(query)}&limit=5`,
                {
                    headers: { "Accept-Language": "en" },
                    signal: abortController.signal,
                },
            );
            if (!response.ok) {
                throw new Error(`Location search failed: ${response.status}`);
            }
            const data = (await response.json()) as NominatimResult[];
            if (
                searchRequestIdRef.current !== requestId ||
                abortController.signal.aborted
            )
                return;
            setSearchResults(data);
            setShowResults(data.length > 0);
        } catch (error) {
            if (
                abortController.signal.aborted ||
                searchRequestIdRef.current !== requestId
            )
                return;
            log.error("Location search failed", error);
            setSearchResults([]);
            setShowResults(false);
        } finally {
            if (
                searchRequestIdRef.current === requestId &&
                !abortController.signal.aborted
            ) {
                setIsSearching(false);
                searchAbortRef.current = null;
            }
        }
    }, []);

    const handleSearchChange = (query: string) => {
        clearTimeout(searchTimeoutRef.current);
        searchAbortRef.current?.abort();
        searchRequestIdRef.current++;
        setSearchQuery(query);
        setIsSearching(false);
        setSearchResults([]);
        setShowResults(false);
        if (query.trim().length >= 3) {
            searchTimeoutRef.current = setTimeout(() => {
                void searchLocations(query.trim());
            }, 1200);
        }
    };

    const handleSearchSubmit = (event: React.SubmitEvent<HTMLFormElement>) => {
        event.preventDefault();
        clearTimeout(searchTimeoutRef.current);
        const query =
            searchInputRef.current?.value.trim() ?? searchQuery.trim();
        if (isSearching || query.length < 3) return;
        void searchLocations(query);
    };

    const handleSelectResult = (result: NominatimResult) => {
        clearTimeout(searchTimeoutRef.current);
        const lat = parseFloat(result.lat);
        const lng = parseFloat(result.lon);
        onLocationSelect({ latitude: lat, longitude: lng });

        if (mapRef.current) {
            mapRef.current.setView([lat, lng], 12);

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

    const parseCoordinates = (
        latValue: string | null,
        lonValue: string | null,
    ): Location | undefined => {
        const latitude =
            latValue === null
                ? selectedLocation?.latitude
                : latValue.trim()
                  ? Number(latValue)
                  : undefined;
        const longitude =
            lonValue === null
                ? selectedLocation?.longitude
                : lonValue.trim()
                  ? Number(lonValue)
                  : undefined;
        if (
            latitude === undefined ||
            longitude === undefined ||
            !Number.isFinite(latitude) ||
            !Number.isFinite(longitude) ||
            latitude < -90 ||
            latitude > 90 ||
            longitude < -180 ||
            longitude > 180
        )
            return undefined;
        return { latitude, longitude };
    };

    const handleCoordinateChange = (
        axis: "latitude" | "longitude",
        value: string,
    ) => {
        const nextLat = axis === "latitude" ? value : manualLat;
        const nextLon = axis === "longitude" ? value : manualLon;
        if (axis === "latitude") setManualLat(value);
        else setManualLon(value);
        const location = parseCoordinates(nextLat, nextLon);
        onCoordinateDraftChange(location, !!location);
        setCoordinateError(false);
    };

    const handleManualCoordinates = () => {
        if (manualLat === null && manualLon === null) return;
        const location = parseCoordinates(manualLat, manualLon);
        if (!location) {
            setCoordinateError(true);
            return;
        }
        onLocationSelect(location);
        mapRef.current?.setView([location.latitude, location.longitude], 12);
        setManualLat(null);
        setManualLon(null);
        onCoordinateDraftChange(undefined, true);
    };

    const urlTemplate = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
    const attribution =
        '&copy; <a target="_blank" rel="noopener" href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';

    useEffect(() => {
        if (!open) return;
        setIsSearching(false);
        return () => {
            clearTimeout(searchTimeoutRef.current);
            searchAbortRef.current?.abort();
        };
    }, [open]);

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

        if (mapRef.current) return;

        const initLoc = initialLocationRef.current;
        const initialLat = initLoc?.latitude;
        const initialLng = initLoc?.longitude;

        const defaultCenter: L.LatLngTuple = [20, 0];
        const defaultZoom = 2;

        const hasInitialLocation =
            initialLat !== undefined && initialLng !== undefined;
        const center: L.LatLngTuple = hasInitialLocation
            ? [initialLat, initialLng]
            : defaultCenter;
        const zoom = hasInitialLocation ? 11 : defaultZoom;

        const map = leaflet
            .map(mapContainer, { zoomControl: false })
            .setView(center, zoom);
        leaflet
            .tileLayer(urlTemplate, {
                attribution,
                referrerPolicy: "strict-origin-when-cross-origin",
            })
            .addTo(map);
        mapRef.current = map;

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
        <Stack sx={{ gap: "20px" }}>
            <ClickAwayListener onClickAway={() => setShowResults(false)}>
                <Box
                    component="form"
                    onSubmit={handleSearchSubmit}
                    sx={{ position: "relative", zIndex: 1001 }}
                >
                    <InputBase
                        placeholder={t("search_location")}
                        value={searchQuery}
                        onChange={(e) => handleSearchChange(e.target.value)}
                        onFocus={() =>
                            searchResults.length > 0 && setShowResults(true)
                        }
                        inputRef={searchInputRef}
                        inputProps={{
                            "aria-label": t("search_location"),
                            enterKeyHint: "search",
                        }}
                        startAdornment={
                            <SearchIcon
                                sx={{
                                    fontSize: 18,
                                    color: "text.muted",
                                    mr: "12px",
                                }}
                            />
                        }
                        endAdornment={
                            isSearching ? (
                                <CircularProgress
                                    size={18}
                                    sx={{ color: "text.muted", ml: 1 }}
                                />
                            ) : undefined
                        }
                        sx={[
                            ...(isSxArray(v2InputSx) ? v2InputSx : [v2InputSx]),
                            { width: "100%", boxSizing: "border-box" },
                        ]}
                    />
                    {showResults && (
                        <SearchResultsList>
                            {searchResults.map((result) => (
                                <ButtonBase
                                    key={result.place_id}
                                    onClick={() => handleSelectResult(result)}
                                    sx={{
                                        width: "100%",
                                        p: "16px",
                                        justifyContent: "flex-start",
                                        textAlign: "left",
                                        "&:hover, &.Mui-focusVisible": {
                                            bgcolor: "fill.faintHover",
                                        },
                                    }}
                                >
                                    <Typography variant="small">
                                        {result.display_name}
                                    </Typography>
                                </ButtonBase>
                            ))}
                        </SearchResultsList>
                    )}
                </Box>
            </ClickAwayListener>
            <Box
                sx={{
                    position: "relative",
                    height: 260,
                    borderRadius: "16px",
                    overflow: "hidden",
                }}
            >
                <Box
                    ref={mapContainerRef}
                    sx={{ height: "100%", width: "100%" }}
                />
                <Stack
                    sx={{
                        position: "absolute",
                        right: 12,
                        bottom: 28,
                        zIndex: 1000,
                        borderRadius: "16px",
                        overflow: "hidden",
                    }}
                >
                    <ZoomButton
                        onClick={handleZoomIn}
                        aria-label={t("zoom_in")}
                    >
                        <AddIcon sx={{ fontSize: 20 }} />
                    </ZoomButton>
                    <ZoomButton
                        onClick={handleZoomOut}
                        aria-label={t("zoom_out")}
                    >
                        <RemoveIcon sx={{ fontSize: 20 }} />
                    </ZoomButton>
                </Stack>
            </Box>
            <Box>
                <Stack
                    direction="row"
                    sx={{ gap: "12px" }}
                    onKeyDown={(event) => {
                        if (event.key === "Enter") {
                            event.preventDefault();
                            handleManualCoordinates();
                        }
                    }}
                >
                    {(
                        [
                            {
                                id: latitudeID,
                                label: t("latitude"),
                                value:
                                    manualLat ??
                                    selectedLocation?.latitude.toFixed(6) ??
                                    "",
                                axis: "latitude",
                                min: -90,
                                max: 90,
                            },
                            {
                                id: longitudeID,
                                label: t("longitude"),
                                value:
                                    manualLon ??
                                    selectedLocation?.longitude.toFixed(6) ??
                                    "",
                                axis: "longitude",
                                min: -180,
                                max: 180,
                            },
                        ] as const
                    ).map(({ id, label, value, axis, min, max }) => (
                        <Stack
                            key={id}
                            sx={{ flex: 1, minWidth: 0, gap: "8px" }}
                        >
                            <Typography
                                component="label"
                                htmlFor={id}
                                sx={v2LabelSx}
                            >
                                {label}
                            </Typography>
                            <InputBase
                                id={id}
                                type="number"
                                value={value}
                                onChange={(event) =>
                                    handleCoordinateChange(
                                        axis,
                                        event.target.value,
                                    )
                                }
                                onBlur={handleManualCoordinates}
                                error={coordinateError}
                                aria-describedby={
                                    coordinateError
                                        ? coordinateErrorID
                                        : undefined
                                }
                                inputProps={{
                                    step: "any",
                                    min,
                                    max,
                                    inputMode: "decimal",
                                }}
                                sx={[
                                    ...(isSxArray(v2InputSx)
                                        ? v2InputSx
                                        : [v2InputSx]),
                                    {
                                        boxSizing: "border-box",
                                        "& input": {
                                            minWidth: 0,
                                            fontVariantNumeric: "tabular-nums",
                                            MozAppearance: "textfield",
                                            "&::-webkit-outer-spin-button, &::-webkit-inner-spin-button":
                                                {
                                                    WebkitAppearance: "none",
                                                    m: 0,
                                                },
                                        },
                                    },
                                ]}
                            />
                        </Stack>
                    ))}
                </Stack>
                {coordinateError && (
                    <Typography
                        id={coordinateErrorID}
                        role="alert"
                        sx={[v2HelperSx(true), { mt: 1 }]}
                    >
                        {t("invalid_location_coordinates")}
                    </Typography>
                )}
            </Box>
        </Stack>
    );
};

const ZoomButton = styled(IconButton)(({ theme }) => ({
    backgroundColor: theme.vars.palette.background.paper,
    color: theme.vars.palette.text.base,
    width: 38,
    height: 38,
    borderRadius: 0,
    "& + &": { borderTop: `1px solid ${theme.vars.palette.divider}` },
    "&:hover": { backgroundColor: theme.vars.palette.background.elevatedPaper },
}));

const SearchResultsList = styled("div")(({ theme }) => ({
    position: "absolute",
    top: "100%",
    left: 0,
    right: 0,
    marginTop: theme.spacing(1),
    backgroundColor: theme.vars.palette.background.paper,
    borderRadius: "16px",
    overflow: "hidden",
    maxHeight: 250,
    overflowY: "auto",
    boxShadow: theme.shadows[4],
}));
