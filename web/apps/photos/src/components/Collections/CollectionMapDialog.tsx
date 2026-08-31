import type { RemotePullOpts } from "@/components/gallery";
import type { SelectedState } from "@/utils/file";
import AddIcon from "@mui/icons-material/Add";
import CloseIcon from "@mui/icons-material/Close";
import LocationOnIcon from "@mui/icons-material/LocationOn";
import RemoveIcon from "@mui/icons-material/Remove";
import {
    Box,
    Dialog,
    DialogContent,
    IconButton,
    Stack,
    styled,
    Typography,
    useMediaQuery,
    type IconButtonProps,
} from "@mui/material";
import { useTheme } from "@mui/material/styles";
import { ensureLocalUser } from "ente-accounts/services/user";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { downloadManager } from "ente-gallery/services/download";
import { uniqueFilesByID } from "ente-gallery/utils/file";
import type { EnteFile } from "ente-media/file";
import {
    fileCreationPhotoSortTime,
    fileLocation,
    ItemVisibility,
    metadataHash,
} from "ente-media/file-metadata";
import {
    addToFavoritesCollection,
    removeFromFavoritesCollection,
} from "ente-new/photos/services/collection";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { updateFilesVisibility } from "ente-new/photos/services/file";
import { t } from "i18next";
import "leaflet/dist/leaflet.css";
import React, {
    startTransition,
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";
import Supercluster, {
    type ClusterFeature,
    type ClusterOrPoint,
    type PointFeature,
} from "supercluster";
import type { FileListWithViewerProps } from "../FileListWithViewer";
import { FileListWithViewer } from "../FileListWithViewer";

interface MapFileSource {
    collectionFiles: EnteFile[];
    favoriteFileIDs: Set<number>;
    hiddenFileIDs: Set<number>;
    archivedFileIDs: Set<number>;
    tempDeletedFileIDs: Set<number>;
    tempHiddenFileIDs: Set<number>;
}

interface CollectionMapDialogProps
    extends
        ModalVisibilityProps,
        Pick<
            FileListWithViewerProps,
            | "onAddSaveGroup"
            | "onMarkTempDeleted"
            | "onAddFileToCollection"
            | "onRemoteFilesPull"
            | "onVisualFeedback"
            | "fileNormalCollectionIDs"
            | "collectionNameByID"
            | "onSelectCollection"
            | "onSelectPerson"
            | "emailByUserID"
        > {
    collectionSummary: CollectionSummary;
    files: EnteFile[];
    mapFileSource: MapFileSource;
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
}

interface MapDataState {
    mapCenter: [number, number] | null;
    mapIndex: MapIndex | null;
    mapPoints: MapIndexPoint[];
    latestFileId: number | undefined;
    filesByID: Map<number, EnteFile>;
    thumbByFileID: Map<number, string>;
    isLoading: boolean;
    error: string | null;
}

interface FavoritesState {
    favoriteFileIDs: Set<number>;
    pendingFavoriteUpdates: Set<number>;
    pendingVisibilityUpdates: Set<number>;
}

interface MapDataResult extends MapDataState {
    removeFiles: (fileIDs: number[]) => void;
    updateFileVisibility: (file: EnteFile, visibility: ItemVisibility) => void;
    queueThumbnailFetch: (fileIDs: number[]) => void;
}

type MapComponents = typeof import("react-leaflet");

interface MapIndexPoint {
    fileId: number;
    lat: number;
    lng: number;
    timestamp: number;
}

interface MapPointProperties {
    fileId: number;
    timestamp: number;
    cluster?: false;
}

type MapPointFeature = PointFeature<MapPointProperties>;

interface MapClusterProperties {
    latestTimestamp: number;
    latestFileId: number;
}

type MapClusterFeature = ClusterFeature<MapClusterProperties>;

type MapFeature = ClusterOrPoint<MapPointProperties, MapClusterProperties>;
type MapIndex = Supercluster<MapPointProperties, MapClusterProperties>;

const MAX_MAP_ZOOM = 19;
const DEFAULT_MAP_ZOOM = 10;
const PREFETCH_BOUNDS_PADDING = 0.15;
const THUMBNAIL_BATCH_SIZE = 40;

function useMapComponents() {
    const [mapComponents, setMapComponents] = useState<MapComponents | null>(
        null,
    );

    useEffect(() => {
        // Static react-leaflet imports break SSR.
        if (typeof window === "undefined") return;

        void import("react-leaflet")
            .then(setMapComponents)
            .catch((e: unknown) => {
                console.error("Failed to load map components", e);
            });
    }, []);

    return mapComponents;
}

function useCurrentUser() {
    return useMemo(() => {
        try {
            return ensureLocalUser();
        } catch {
            return undefined;
        }
    }, []);
}

const favoriteFileHashAndTypeKey = (file: EnteFile) => {
    const hash = metadataHash(file.metadata);
    return hash ? `${hash}:${file.metadata.fileType}` : undefined;
};

interface DeriveLocationAwareMapFilesParams {
    files: EnteFile[];
    collectionFiles: EnteFile[];
    collectionSummaryType: CollectionSummary["type"];
    currentUserID: number | undefined;
    favoriteFileIDs: Set<number>;
    hiddenFileIDs: Set<number>;
    archivedFileIDs: Set<number>;
    tempDeletedFileIDs: Set<number>;
    tempHiddenFileIDs: Set<number>;
}

const canUseFileAsMapEquivalent = (
    file: EnteFile,
    hiddenFileIDs: Set<number>,
    archivedFileIDs: Set<number>,
    tempDeletedFileIDs: Set<number>,
    tempHiddenFileIDs: Set<number>,
) =>
    // A mutation can be remote before the next pull updates collectionFiles.
    !tempDeletedFileIDs.has(file.id) &&
    !hiddenFileIDs.has(file.id) &&
    !tempHiddenFileIDs.has(file.id) &&
    !archivedFileIDs.has(file.id) &&
    (file.magicMetadata?.data.visibility === undefined ||
        file.magicMetadata.data.visibility === ItemVisibility.visible);

const addUniqueMapFile = (
    files: EnteFile[],
    fileIDs: Set<number>,
    file: EnteFile,
) => {
    if (fileIDs.has(file.id)) return;
    fileIDs.add(file.id);
    files.push(file);
};

const deriveLocationAwareMapFiles = ({
    files,
    collectionFiles,
    collectionSummaryType,
    currentUserID,
    favoriteFileIDs,
    hiddenFileIDs,
    archivedFileIDs,
    tempDeletedFileIDs,
    tempHiddenFileIDs,
}: DeriveLocationAwareMapFilesParams) => {
    if (
        !currentUserID ||
        (collectionSummaryType != "all" &&
            collectionSummaryType != "userFavorites")
    ) {
        return files;
    }

    const filesByHashAndType = new Map<string, EnteFile[]>();
    for (const file of collectionFiles) {
        if (
            !canUseFileAsMapEquivalent(
                file,
                hiddenFileIDs,
                archivedFileIDs,
                tempDeletedFileIDs,
                tempHiddenFileIDs,
            )
        ) {
            continue;
        }

        const key = favoriteFileHashAndTypeKey(file);

        if (!key) continue;

        const matchingFiles = filesByHashAndType.get(key);
        if (matchingFiles) {
            matchingFiles.push(file);
        } else {
            filesByHashAndType.set(key, [file]);
        }
    }

    const mapFiles: EnteFile[] = [];
    const mapFileIDs = new Set<number>();

    for (const file of files) {
        const key = favoriteFileHashAndTypeKey(file);
        const equivalentFiles = key ? filesByHashAndType.get(key) : undefined;

        if (!equivalentFiles) {
            addUniqueMapFile(mapFiles, mapFileIDs, file);
            continue;
        }

        if (
            collectionSummaryType == "all" &&
            !equivalentFiles.some((equivalentFile) =>
                favoriteFileIDs.has(equivalentFile.id),
            )
        ) {
            addUniqueMapFile(mapFiles, mapFileIDs, file);
            continue;
        }

        const ownedFiles = equivalentFiles.filter(
            (equivalentFile) => equivalentFile.ownerID == currentUserID,
        );
        const sharedFiles = equivalentFiles.filter(
            (equivalentFile) => equivalentFile.ownerID != currentUserID,
        );

        if (!ownedFiles.length || !sharedFiles.length) {
            addUniqueMapFile(mapFiles, mapFileIDs, file);
            continue;
        }

        const ownedFilesWithLocation = ownedFiles.filter(fileLocation);
        const sharedFilesWithLocation = sharedFiles.filter(fileLocation);

        const filesWithLocation = [
            ...sharedFilesWithLocation,
            ...ownedFilesWithLocation,
        ];
        for (const mapFile of filesWithLocation.length
            ? filesWithLocation
            : [file]) {
            addUniqueMapFile(mapFiles, mapFileIDs, mapFile);
        }
    }

    return mapFiles;
};

const buildMapIndexPoints = async (files: EnteFile[]) => {
    const points: MapIndexPoint[] = [];
    let latestTimestamp = -1;
    let latestFileId: number | undefined;

    for (let index = 0; index < files.length; index += 1) {
        const file = files[index];
        if (!file) continue;
        const loc = fileLocation(file);
        if (!loc) continue;

        const timestamp = fileCreationPhotoSortTime(file);
        points.push({
            fileId: file.id,
            lat: loc.latitude,
            lng: loc.longitude,
            timestamp,
        });

        if (timestamp > latestTimestamp) {
            latestTimestamp = timestamp;
            latestFileId = file.id;
        }

        // Keep 100k-file collections responsive.
        if (index > 0 && index % 5000 === 0) {
            await new Promise((resolve) => setTimeout(resolve, 0));
        }
    }

    return { points, latestFileId };
};

const buildClusterIndex = (points: MapIndexPoint[]): MapIndex => {
    const index = new Supercluster<MapPointProperties, MapClusterProperties>({
        radius: 80,
        maxZoom: MAX_MAP_ZOOM,
        map: (props) => ({
            latestTimestamp: props.timestamp,
            latestFileId: props.fileId,
        }),
        reduce: (accumulated, props) => {
            if (props.latestTimestamp > accumulated.latestTimestamp) {
                accumulated.latestTimestamp = props.latestTimestamp;
                accumulated.latestFileId = props.latestFileId;
            }
        },
    });

    const features: MapPointFeature[] = points.map((point) => ({
        type: "Feature" as const,
        properties: { fileId: point.fileId, timestamp: point.timestamp },
        geometry: {
            type: "Point" as const,
            coordinates: [point.lng, point.lat] as [number, number],
        },
    }));

    index.load(features);
    return index;
};

const buildMapIndex = (points: MapIndexPoint[]) =>
    points.length > 0 ? buildClusterIndex(points) : null;

const getPointByFileId = (
    points: MapIndexPoint[],
    fileId: number | undefined,
) => {
    if (fileId === undefined) return undefined;
    return points.find((point) => point.fileId === fileId);
};

const getLatestPointByTimestamp = (
    points: MapIndexPoint[],
): MapIndexPoint | undefined => {
    let latest: MapIndexPoint | undefined;
    for (const point of points) {
        if (!latest || point.timestamp > latest.timestamp) {
            latest = point;
        }
    }
    return latest;
};

const getLatestFileIdFromPoints = (points: MapIndexPoint[]) =>
    getLatestPointByTimestamp(points)?.fileId;

const emptyMapDataState = (): MapDataState => ({
    mapCenter: null,
    mapIndex: null,
    mapPoints: [],
    latestFileId: undefined,
    filesByID: new Map(),
    thumbByFileID: new Map(),
    isLoading: false,
    error: null,
});

function useMapData(
    open: boolean,
    collectionSummary: CollectionSummary,
    files: EnteFile[],
    onGenericError: (e: unknown) => void,
): MapDataResult {
    const [state, setState] = useState<MapDataState>(emptyMapDataState);

    const filesByIDRef = useRef<Map<number, EnteFile>>(new Map());
    const thumbsByFileIDRef = useRef<Map<number, string>>(new Map());
    const pendingThumbsRef = useRef<Set<number>>(new Set());
    const isThumbnailWorkerRunningRef = useRef(false);

    const loadedCollectionRef = useRef<{
        summaryId: number;
        fileCount: number;
        updationTime: number | null;
        files: EnteFile[];
    } | null>(null);
    const lastLoadedSummaryIdRef = useRef<number | undefined>(undefined);
    // Closing or a newer load invalidates in-flight work.
    const loadGenerationRef = useRef(0);

    useEffect(() => {
        filesByIDRef.current = state.filesByID;
    }, [state.filesByID]);

    useEffect(() => {
        thumbsByFileIDRef.current = state.thumbByFileID;
    }, [state.thumbByFileID]);

    const queueThumbnailFetch = useCallback((fileIDs: number[]) => {
        if (!fileIDs.length) return;

        const pending = pendingThumbsRef.current;
        const existingThumbs = thumbsByFileIDRef.current;
        const filesByID = filesByIDRef.current;

        for (const fileId of fileIDs) {
            if (existingThumbs.has(fileId)) continue;
            if (!filesByID.has(fileId)) continue;
            pending.add(fileId);
        }

        if (isThumbnailWorkerRunningRef.current) return;
        isThumbnailWorkerRunningRef.current = true;

        void (async () => {
            while (pendingThumbsRef.current.size > 0) {
                const batchIds = Array.from(pendingThumbsRef.current).slice(
                    0,
                    THUMBNAIL_BATCH_SIZE,
                );
                batchIds.forEach((id) => pendingThumbsRef.current.delete(id));

                const entries = await Promise.all(
                    batchIds.map(async (fileId) => {
                        const file = filesByIDRef.current.get(fileId);
                        if (!file) return [fileId, undefined] as const;
                        try {
                            const thumb =
                                await downloadManager.renderableThumbnailURL(
                                    file,
                                );
                            return [fileId, thumb] as const;
                        } catch {
                            return [fileId, undefined] as const;
                        }
                    }),
                );

                setState((prev) => {
                    const updatedThumbMap = new Map(prev.thumbByFileID);
                    entries.forEach(([fileId, thumbnailUrl]) => {
                        if (!thumbnailUrl || updatedThumbMap.has(fileId))
                            return;
                        updatedThumbMap.set(fileId, thumbnailUrl);
                    });
                    return updatedThumbMap.size > prev.thumbByFileID.size
                        ? { ...prev, thumbByFileID: updatedThumbMap }
                        : prev;
                });

                await new Promise((resolve) => setTimeout(resolve, 0));
            }

            isThumbnailWorkerRunningRef.current = false;
        })();
    }, []);

    useEffect(() => {
        if (!open) {
            loadedCollectionRef.current = null;
            loadGenerationRef.current += 1;
            pendingThumbsRef.current.clear();
            isThumbnailWorkerRunningRef.current = false;
        }
    }, [open]);

    useEffect(() => {
        if (!open) return;

        const currentSummaryId = collectionSummary.id;
        const currentFileCount = collectionSummary.fileCount;
        const currentUpdationTime = collectionSummary.updationTime ?? null;
        const loaded = loadedCollectionRef.current;

        // Pulls replace the array, so compare revisions to catch real edits only.
        const sameFiles =
            loaded?.files === files ||
            (!!loaded &&
                loaded.files.length === files.length &&
                loaded.files.every((file, index) => {
                    const nextFile = files[index];
                    return (
                        file.id === nextFile?.id &&
                        file.collectionID === nextFile.collectionID &&
                        file.updationTime === nextFile.updationTime
                    );
                }));

        if (
            loaded?.summaryId === currentSummaryId &&
            loaded.fileCount === currentFileCount &&
            loaded.updationTime === currentUpdationTime &&
            sameFiles
        ) {
            return;
        }

        const loadMapData = async () => {
            const generation = ++loadGenerationRef.current;
            pendingThumbsRef.current.clear();
            // Clear stale maps on a switch; keep background reloads mounted.
            const isNewCollection =
                lastLoadedSummaryIdRef.current !== currentSummaryId;
            setState((prev) =>
                isNewCollection
                    ? { ...emptyMapDataState(), isLoading: true }
                    : { ...prev, isLoading: true, error: null },
            );

            try {
                const uniqueFiles = uniqueFilesByID(files);

                const filesByID = new Map(
                    uniqueFiles.map((file) => [file.id, file]),
                );
                filesByIDRef.current = filesByID;

                const { points, latestFileId } =
                    await buildMapIndexPoints(uniqueFiles);
                if (generation !== loadGenerationRef.current) return;

                const mapIndex = buildMapIndex(points);

                const latestPoint =
                    getPointByFileId(points, latestFileId) ?? points[0];

                const mapCenter: [number, number] | null = latestPoint
                    ? [latestPoint.lat, latestPoint.lng]
                    : null;

                setState((prev) => ({
                    filesByID,
                    mapCenter,
                    mapIndex,
                    mapPoints: points,
                    latestFileId,
                    // Keep already-fetched thumbnails; keys are file ids so
                    // entries for removed files are simply unused.
                    thumbByFileID: prev.thumbByFileID,
                    isLoading: false,
                    error: null,
                }));

                loadedCollectionRef.current = {
                    summaryId: currentSummaryId,
                    fileCount: currentFileCount,
                    updationTime: currentUpdationTime,
                    files,
                };
                lastLoadedSummaryIdRef.current = currentSummaryId;

                const coverId = collectionSummary.coverFile?.id ?? latestFileId;
                if (coverId !== undefined) {
                    queueThumbnailFetch([coverId]);
                }

                return;
            } catch (e) {
                if (generation !== loadGenerationRef.current) return;
                setState((prev) => ({
                    ...prev,
                    isLoading: false,
                    error: t("something_went_wrong"),
                }));
                onGenericError(e);
            } finally {
                if (generation === loadGenerationRef.current) {
                    setState((prev) =>
                        prev.isLoading ? { ...prev, isLoading: false } : prev,
                    );
                }
            }
        };

        void loadMapData();
    }, [open, collectionSummary, files, onGenericError, queueThumbnailFetch]);

    const removeFiles = useCallback((fileIDs: number[]) => {
        if (!fileIDs.length) return;
        setState((prev) => {
            const ids = new Set(fileIDs);
            const filesByID = new Map(prev.filesByID);
            const thumbByFileID = new Map(prev.thumbByFileID);
            ids.forEach((id) => {
                filesByID.delete(id);
                thumbByFileID.delete(id);
            });
            const mapPoints = prev.mapPoints.filter(
                (point) => !ids.has(point.fileId),
            );
            const mapIndex = buildMapIndex(mapPoints);

            let latestFileId = prev.latestFileId;
            if (latestFileId && ids.has(latestFileId)) {
                latestFileId = getLatestFileIdFromPoints(mapPoints);
            }
            return {
                ...prev,
                filesByID,
                thumbByFileID,
                mapIndex,
                mapPoints,
                latestFileId,
                mapCenter: mapPoints.length ? prev.mapCenter : null,
            };
        });
    }, []);

    const updateFileVisibility = useCallback(
        (file: EnteFile, visibility: ItemVisibility) => {
            setState((prev) => {
                if (!prev.filesByID.has(file.id)) return prev;
                if (!file.magicMetadata) return prev;

                const updatedMagicMetadata = {
                    ...file.magicMetadata,
                    data: { ...file.magicMetadata.data, visibility },
                };

                const updatedFile: EnteFile = {
                    ...file,
                    magicMetadata: updatedMagicMetadata,
                };
                const filesByID = new Map(prev.filesByID);
                filesByID.set(file.id, updatedFile);

                let mapPoints = prev.mapPoints;
                let mapIndex = prev.mapIndex;
                let latestFileId = prev.latestFileId;

                if (visibility !== ItemVisibility.visible) {
                    const filtered = prev.mapPoints.filter(
                        (point) => point.fileId !== file.id,
                    );
                    if (filtered.length !== prev.mapPoints.length) {
                        mapPoints = filtered;
                        mapIndex = buildMapIndex(mapPoints);
                        if (latestFileId === file.id) {
                            latestFileId = getLatestFileIdFromPoints(mapPoints);
                        }
                    }
                } else if (!prev.mapPoints.some((p) => p.fileId === file.id)) {
                    const loc = fileLocation(file);
                    if (loc) {
                        const timestamp = fileCreationPhotoSortTime(file);
                        mapPoints = [
                            ...prev.mapPoints,
                            {
                                fileId: file.id,
                                lat: loc.latitude,
                                lng: loc.longitude,
                                timestamp,
                            },
                        ];

                        mapIndex = buildMapIndex(mapPoints);
                        const latestPoint =
                            latestFileId !== undefined
                                ? getPointByFileId(prev.mapPoints, latestFileId)
                                : undefined;
                        if (!latestPoint || timestamp > latestPoint.timestamp) {
                            latestFileId = file.id;
                        }
                    }
                }

                let mapCenter = prev.mapCenter;
                if (!mapPoints.length) {
                    mapCenter = null;
                } else if (!mapCenter) {
                    const centerPoint =
                        latestFileId !== undefined
                            ? mapPoints.find(
                                  (point) => point.fileId === latestFileId,
                              )
                            : mapPoints[0];
                    if (centerPoint) {
                        mapCenter = [centerPoint.lat, centerPoint.lng];
                    }
                }

                return {
                    ...prev,
                    filesByID,
                    mapPoints,
                    mapIndex,
                    latestFileId,
                    mapCenter,
                };
            });
        },
        [],
    );

    return { ...state, removeFiles, updateFileVisibility, queueThumbnailFetch };
}

function useFavorites(
    open: boolean,
    user: ReturnType<typeof useCurrentUser>,
    favoriteEquivalenceFiles: EnteFile[],
    syncedFavoriteFileIDs: Set<number>,
): FavoritesState & {
    handleToggleFavorite: (file: EnteFile) => Promise<void>;
    handleFileVisibilityUpdate: (
        file: EnteFile,
        visibility: ItemVisibility,
    ) => Promise<void>;
} {
    const [favoriteFileIDs, setFavoriteFileIDs] = useState(
        syncedFavoriteFileIDs,
    );
    const [pendingFavoriteUpdates, setPendingFavoriteUpdates] = useState<
        Set<number>
    >(new Set());
    const [pendingVisibilityUpdates, setPendingVisibilityUpdates] = useState<
        Set<number>
    >(new Set());

    useEffect(() => {
        if (open && user) setFavoriteFileIDs(syncedFavoriteFileIDs);
    }, [open, syncedFavoriteFileIDs, user]);

    const addToSet = useCallback((set: Set<number>, id: number) => {
        if (set.has(id)) return set;
        const next = new Set(set);
        next.add(id);
        return next;
    }, []);

    const removeFromSet = useCallback((set: Set<number>, id: number) => {
        if (!set.has(id)) return set;
        const next = new Set(set);
        next.delete(id);
        return next;
    }, []);

    const addIDsToSet = useCallback((set: Set<number>, ids: number[]) => {
        let next: Set<number> | undefined;
        for (const id of ids) {
            if (set.has(id) || next?.has(id)) continue;
            next ??= new Set(set);
            next.add(id);
        }
        return next ?? set;
    }, []);

    const removeIDsFromSet = useCallback((set: Set<number>, ids: number[]) => {
        let next: Set<number> | undefined;
        for (const id of ids) {
            if (!set.has(id) && !next?.has(id)) continue;
            next ??= new Set(set);
            next.delete(id);
        }
        return next ?? set;
    }, []);

    const favoriteEquivalentFileIDs = useCallback(
        (file: EnteFile) => {
            const key = favoriteFileHashAndTypeKey(file);

            if (!key) return [file.id];

            const isSharedSourceFile = file.ownerID != user?.id;
            let firstOwnedEquivalentID: number | undefined;
            let hasFavoritedOwnedEquivalent = false;

            const fileIDs = new Set([file.id]);

            for (const equivalentFile of favoriteEquivalenceFiles) {
                if (favoriteFileHashAndTypeKey(equivalentFile) != key) {
                    continue;
                }

                if (equivalentFile.ownerID != user?.id) {
                    fileIDs.add(equivalentFile.id);
                    continue;
                }

                if (favoriteFileIDs.has(equivalentFile.id)) {
                    hasFavoritedOwnedEquivalent = true;
                    fileIDs.add(equivalentFile.id);
                } else {
                    firstOwnedEquivalentID ??= equivalentFile.id;
                }
            }

            if (
                isSharedSourceFile &&
                !hasFavoritedOwnedEquivalent &&
                firstOwnedEquivalentID !== undefined
            ) {
                fileIDs.add(firstOwnedEquivalentID);
            }

            return [...fileIDs];
        },
        [favoriteEquivalenceFiles, favoriteFileIDs, user?.id],
    );

    const handleToggleFavorite = useCallback(
        async (file: EnteFile) => {
            if (!user) return;
            const fileID = file.id;
            const fileIDs = favoriteEquivalentFileIDs(file);

            const isFavorite = favoriteFileIDs.has(fileID);

            setPendingFavoriteUpdates((prev) => addIDsToSet(prev, fileIDs));
            try {
                const action = isFavorite
                    ? removeFromFavoritesCollection
                    : addToFavoritesCollection;
                await action([file]);
                setFavoriteFileIDs((prev) =>
                    isFavorite
                        ? removeIDsFromSet(prev, fileIDs)
                        : addIDsToSet(prev, fileIDs),
                );
            } finally {
                setPendingFavoriteUpdates((prev) =>
                    removeIDsFromSet(prev, fileIDs),
                );
            }
        },
        [
            user,
            favoriteFileIDs,
            favoriteEquivalentFileIDs,
            addIDsToSet,
            removeIDsFromSet,
        ],
    );

    const handleFileVisibilityUpdate = useCallback(
        async (file: EnteFile, visibility: ItemVisibility) => {
            const fileID = file.id;
            setPendingVisibilityUpdates((prev) => addToSet(prev, fileID));
            try {
                await updateFilesVisibility([file], visibility);
            } finally {
                setPendingVisibilityUpdates((prev) =>
                    removeFromSet(prev, fileID),
                );
            }
        },
        [addToSet, removeFromSet],
    );

    return {
        favoriteFileIDs,
        pendingFavoriteUpdates,
        pendingVisibilityUpdates,
        handleToggleFavorite,
        handleFileVisibilityUpdate,
    };
}

function createMarkerIcon(
    imageSrc: string,
    clusterCount?: number,
    interactive = true,
): import("leaflet").DivIcon | null {
    if (typeof window === "undefined") return null;

    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const leaflet = require("leaflet") as typeof import("leaflet");

    const pinSize = 84;
    const triangleHeight = 10;
    const pinHeight = pinSize + triangleHeight + 2;
    const hasImage = imageSrc.trim() !== "";
    const isCluster = clusterCount !== undefined;
    const badgeOverflow = isCluster ? 6 : 0;

    const outerBorderRadius = 16;
    const innerBorderRadius = 12;

    const hoverHandlers = interactive
        ? "onmouseover=\"this.style.background='#22c55e'; this.style.borderColor='#22c55e'; this.parentElement.querySelector('.triangle').style.borderTopColor='#22c55e';\" onmouseout=\"this.style.background='white'; this.style.borderColor='#ffffff'; this.parentElement.querySelector('.triangle').style.borderTopColor='white';\""
        : "";

    const badgeLabel =
        clusterCount !== undefined && clusterCount >= 2000
            ? `${Math.floor((clusterCount - 1) / 1000)}K+`
            : clusterCount !== undefined && clusterCount >= 1000
              ? "1K+"
              : `${clusterCount}`;

    return leaflet.divIcon({
        html: `
            <div class="photo-pin" style="
                width: ${pinSize}px;
                height: ${pinHeight}px;
                position: relative;
                cursor: ${interactive ? "pointer" : "default"};
                transition: all 0.3s ease;
                ${isCluster ? "overflow: visible;" : ""}
                filter: drop-shadow(0 4px 8px rgba(0, 0, 0, 0.3)) drop-shadow(0 2px 4px rgba(0, 0, 0, 0.2));
            ">
              <div style="
                  width: ${pinSize}px;
                  height: ${pinSize}px;
                  border-radius: ${outerBorderRadius}px;
                  background: white;
                  border: 2px solid #ffffff;
                  padding: 4px;
                  position: relative;
                  overflow: hidden;
                  transition: background-color 0.3s ease, border-color 0.3s ease;
              "
              ${hoverHandlers}
              >
                ${
                    hasImage
                        ? `<img src="${imageSrc}" style="width:100%;height:100%;object-fit:cover;border-radius:${innerBorderRadius}px;" alt="Location" />`
                        : `<div style="width:100%;height:100%;border-radius:${innerBorderRadius}px;animation:skeleton-pulse 1.5s ease-in-out infinite;"></div>
                           <style>@keyframes skeleton-pulse{0%{background-color:#ffffff}50%{background-color:#f0f0f0}100%{background-color:#ffffff}}</style>`
                }
              </div>
              ${
                  isCluster
                      ? `<div style="
                            position: absolute;
                            top: -${badgeOverflow}px;
                            right: -${badgeOverflow}px;
                            background: #22c55e;
                            color: #ffffff;
                            border-radius: 7px;
                            padding: 4px 7px;
                            font-size: 12px;
                            font-weight: 700;
                            line-height: 1;
                            box-shadow: 0 2px 6px rgba(0,0,0,0.2);
                            z-index: 1;
                         ">${badgeLabel}</div>
                         <style>.leaflet-marker-icon.collection-cluster-marker { overflow: visible !important; }</style>`
                      : ""
              }
              <div class="triangle" style="
                  position: absolute;
                  bottom: 2px;
                  left: 50%;
                  transform: translateX(-50%);
                  width: 0;
                  height: 0;
                  border-left: ${triangleHeight}px solid transparent;
                  border-right: ${triangleHeight}px solid transparent;
                  border-top: ${triangleHeight}px solid white;
                  transition: border-top-color 0.3s ease;
              "></div>
            </div>
        `,
        className: isCluster
            ? "collection-cluster-marker"
            : "collection-marker",
        iconSize: [pinSize + badgeOverflow, pinHeight + badgeOverflow],
        iconAnchor: [pinSize / 2, pinHeight],
    });
}

export const CollectionMapDialog: React.FC<CollectionMapDialogProps> = ({
    open,
    onClose,
    collectionSummary,
    files,
    onRemotePull,
    onAddSaveGroup,
    onMarkTempDeleted,
    onAddFileToCollection,
    onRemoteFilesPull,
    onVisualFeedback,
    fileNormalCollectionIDs,
    collectionNameByID,
    onSelectCollection,
    onSelectPerson,
    mapFileSource,
    emailByUserID,
}) => {
    const { onGenericError } = useBaseContext();
    const mapComponents = useMapComponents();
    const user = useCurrentUser();
    const [isFileViewerOpen, setIsFileViewerOpen] = useState(false);
    const {
        collectionFiles: mapSourceCollectionFiles,
        favoriteFileIDs: syncedFavoriteFileIDs,
        hiddenFileIDs,
        archivedFileIDs,
        tempDeletedFileIDs,
        tempHiddenFileIDs,
    } = mapFileSource;

    const {
        favoriteFileIDs,
        pendingFavoriteUpdates,
        pendingVisibilityUpdates,
        handleToggleFavorite,
        handleFileVisibilityUpdate,
    } = useFavorites(
        open,
        user,
        mapSourceCollectionFiles,
        syncedFavoriteFileIDs,
    );

    const mapFiles = useMemo(
        () =>
            deriveLocationAwareMapFiles({
                files,
                collectionFiles: mapSourceCollectionFiles,
                collectionSummaryType: collectionSummary.type,
                currentUserID: user?.id,
                favoriteFileIDs,
                hiddenFileIDs,
                archivedFileIDs,
                tempDeletedFileIDs,
                tempHiddenFileIDs,
            }),
        [
            collectionSummary.type,
            favoriteFileIDs,
            files,
            archivedFileIDs,
            mapSourceCollectionFiles,
            hiddenFileIDs,
            tempDeletedFileIDs,
            tempHiddenFileIDs,
            user?.id,
        ],
    );

    const {
        mapCenter,
        mapIndex,
        mapPoints,
        latestFileId,
        filesByID,
        thumbByFileID,
        isLoading,
        error,
        removeFiles: removeFilesFromMap,
        updateFileVisibility,
        queueThumbnailFetch,
    } = useMapData(open, collectionSummary, mapFiles, onGenericError);

    const [visibleFileIDs, setVisibleFileIDs] = useState<number[]>([]);
    const [isVisiblePhotosUpdating, setIsVisiblePhotosUpdating] =
        useState(false);

    useEffect(() => {
        if (!open) {
            setIsVisiblePhotosUpdating(false);
        }
    }, [open]);

    const visibleFiles = useMemo(() => {
        return visibleFileIDs
            .map((fileID) => filesByID.get(fileID))
            .filter((f): f is EnteFile => f !== undefined);
    }, [visibleFileIDs, filesByID]);

    const handleRemotePull = useCallback(
        () => onRemotePull({ silent: true, source: "map-dialog" }),
        [onRemotePull],
    );

    const handleMarkTempDeleted = useCallback(
        (files: EnteFile[]) => {
            onMarkTempDeleted?.(files);

            const idsToRemove = new Set(files.map((file) => file.id));
            setVisibleFileIDs((prev) =>
                prev.filter((fileID) => !idsToRemove.has(fileID)),
            );
            removeFilesFromMap([...idsToRemove]);
        },
        [onMarkTempDeleted, removeFilesFromMap],
    );

    const handleFileVisibilityUpdateWithLocalState = useCallback(
        async (file: EnteFile, visibility: ItemVisibility) => {
            await handleFileVisibilityUpdate(file, visibility);
            updateFileVisibility(file, visibility);
        },
        [handleFileVisibilityUpdate, updateFileVisibility],
    );

    let body: React.ReactNode;
    // Background reloads keep the map and viewer mounted.
    if (isLoading && !mapIndex) {
        body = (
            <CenteredBox>
                <ActivityIndicator size="28px" />
            </CenteredBox>
        );
    } else if (error) {
        body = (
            <CenteredBox>
                <Typography variant="body" sx={{ color: "text.secondary" }}>
                    {error}
                </Typography>
            </CenteredBox>
        );
    } else if (!mapComponents) {
        body = (
            <CenteredBox>
                <ActivityIndicator size="28px" />
            </CenteredBox>
        );
    } else if (!mapPoints.length || !mapCenter || !mapIndex) {
        body = (
            <CenteredBox onClose={onClose} closeLabel={t("close")}>
                <Typography variant="body" sx={{ color: "text.secondary" }}>
                    {t("no_geotagged_photos")}
                </Typography>
            </CenteredBox>
        );
    } else {
        body = (
            <Box sx={{ position: "relative", height: "100%", width: "100%" }}>
                <CollectionSidebar
                    collectionSummary={collectionSummary}
                    visibleFiles={visibleFiles}
                    isVisiblePhotosUpdating={isVisiblePhotosUpdating}
                    latestFileId={latestFileId}
                    thumbByFileID={thumbByFileID}
                    onClose={onClose}
                    user={user}
                    favoriteFileIDs={favoriteFileIDs}
                    pendingFavoriteUpdates={pendingFavoriteUpdates}
                    pendingVisibilityUpdates={pendingVisibilityUpdates}
                    onToggleFavorite={handleToggleFavorite}
                    onFileVisibilityUpdate={
                        handleFileVisibilityUpdateWithLocalState
                    }
                    onRemotePull={handleRemotePull}
                    onVisualFeedback={onVisualFeedback}
                    onAddSaveGroup={onAddSaveGroup}
                    onMarkTempDeleted={handleMarkTempDeleted}
                    onAddFileToCollection={onAddFileToCollection}
                    onRemoteFilesPull={onRemoteFilesPull}
                    fileNormalCollectionIDs={fileNormalCollectionIDs}
                    collectionNameByID={collectionNameByID}
                    onSelectCollection={onSelectCollection}
                    onSelectPerson={onSelectPerson}
                    emailByUserID={emailByUserID}
                    onSetOpenFileViewer={setIsFileViewerOpen}
                />
                <Box sx={{ width: "100%", height: "100%" }}>
                    <MapCanvas
                        mapComponents={mapComponents}
                        mapCenter={mapCenter}
                        mapIndex={mapIndex}
                        thumbByFileID={thumbByFileID}
                        onVisibleFileIDsChange={setVisibleFileIDs}
                        onVisiblePhotosLoadingChange={
                            setIsVisiblePhotosUpdating
                        }
                        onPrefetchThumbnails={queueThumbnailFetch}
                    />
                </Box>
            </Box>
        );
    }

    return (
        <Dialog
            fullScreen
            keepMounted
            open={open}
            onClose={onClose}
            sx={{
                // Keep PhotoSwipe above the mounted dialog during transitions.
                ...(isFileViewerOpen && {
                    zIndex: (theme) =>
                        `calc(${theme.zIndex.drawer} - 2) !important`,
                }),
            }}
        >
            <Box
                sx={{
                    position: "relative",
                    width: "100vw",
                    height: "100vh",
                    bgcolor: "background.default",
                }}
            >
                <DialogContent sx={{ padding: "0 !important", height: "100%" }}>
                    {body}
                </DialogContent>
            </Box>
        </Dialog>
    );
};

interface CollectionSidebarProps {
    collectionSummary: CollectionSummary;
    visibleFiles: EnteFile[];
    isVisiblePhotosUpdating: boolean;
    latestFileId: number | undefined;
    thumbByFileID: Map<number, string>;
    onClose: () => void;
    user: ReturnType<typeof useCurrentUser>;
    favoriteFileIDs: Set<number>;
    pendingFavoriteUpdates: Set<number>;
    pendingVisibilityUpdates: Set<number>;
    onToggleFavorite: (file: EnteFile) => Promise<void>;
    onFileVisibilityUpdate: (
        file: EnteFile,
        visibility: ItemVisibility,
    ) => Promise<void>;
    onRemotePull: () => Promise<void>;
    onVisualFeedback: () => void;
    onAddSaveGroup: FileListWithViewerProps["onAddSaveGroup"];
    onMarkTempDeleted?: FileListWithViewerProps["onMarkTempDeleted"];
    onAddFileToCollection?: FileListWithViewerProps["onAddFileToCollection"];
    onRemoteFilesPull?: FileListWithViewerProps["onRemoteFilesPull"];
    fileNormalCollectionIDs?: FileListWithViewerProps["fileNormalCollectionIDs"];
    collectionNameByID?: FileListWithViewerProps["collectionNameByID"];
    onSelectCollection?: FileListWithViewerProps["onSelectCollection"];
    onSelectPerson?: FileListWithViewerProps["onSelectPerson"];
    emailByUserID: FileListWithViewerProps["emailByUserID"];
    onSetOpenFileViewer?: (open: boolean) => void;
}

const COVER_IMAGE_HEIGHT = 320;
const MOBILE_SIDEBAR_HEIGHT = "50%";
const COVER_HEADER_HEIGHT = COVER_IMAGE_HEIGHT + 34;

function CollectionSidebar({
    collectionSummary,
    visibleFiles,
    isVisiblePhotosUpdating,
    latestFileId,
    thumbByFileID,
    onClose,
    user,
    favoriteFileIDs,
    pendingFavoriteUpdates,
    pendingVisibilityUpdates,
    onToggleFavorite,
    onFileVisibilityUpdate,
    onRemotePull,
    onVisualFeedback,
    onAddSaveGroup,
    onMarkTempDeleted,
    onAddFileToCollection,
    onRemoteFilesPull,
    fileNormalCollectionIDs,
    collectionNameByID,
    onSelectCollection,
    onSelectPerson,
    emailByUserID,
    onSetOpenFileViewer,
}: CollectionSidebarProps) {
    const [currentDate, setCurrentDate] = useState<string | undefined>(
        undefined,
    );
    const [scrollOffset, setScrollOffset] = useState(0);
    const shouldShowCover = collectionSummary.type !== "all";
    const theme = useTheme();
    const isDarkMode = theme.palette.mode === "dark";
    const isMobile = useMediaQuery(theme.breakpoints.down("md"));

    const emptySelected = useMemo<SelectedState>(
        () => ({
            ownCount: 0,
            count: 0,
            context: undefined,
            collectionID: collectionSummary.id,
        }),
        [collectionSummary.id],
    );
    const noOpSetSelected = useCallback(() => undefined, []);

    const coverImageUrl =
        (collectionSummary.coverFile &&
            thumbByFileID.get(collectionSummary.coverFile.id)) ||
        (latestFileId ? thumbByFileID.get(latestFileId) : undefined);
    const coverHeader = useMemo(
        () =>
            shouldShowCover
                ? {
                      component: (
                          <MapCover
                              name={collectionSummary.name}
                              coverImageUrl={coverImageUrl}
                              totalCount={collectionSummary.fileCount}
                              onClose={onClose}
                          />
                      ),
                      height: COVER_HEADER_HEIGHT,
                      extendToInlineEdges: true,
                  }
                : undefined,
        [
            shouldShowCover,
            collectionSummary.name,
            collectionSummary.fileCount,
            coverImageUrl,
            onClose,
        ],
    );

    const showStickyHeader =
        !shouldShowCover ||
        (scrollOffset > COVER_HEADER_HEIGHT && !!currentDate);
    const visibleDate =
        currentDate && (scrollOffset > 0 || (shouldShowCover && !isMobile))
            ? currentDate
            : undefined;

    return (
        <SidebarWrapper>
            <SidebarContainer>
                <StickyDateHeader
                    visible={showStickyHeader}
                    variant={shouldShowCover ? "overlay" : "static"}
                >
                    <Box
                        sx={{
                            display: "flex",
                            justifyContent: "space-between",
                            alignItems: "center",
                        }}
                    >
                        <Box>
                            <Typography
                                variant="body"
                                sx={{ fontWeight: 700, fontSize: "18px" }}
                            >
                                {collectionSummary.name}
                            </Typography>
                            <Typography
                                variant="small"
                                sx={{ color: "text.muted", fontSize: "14px" }}
                            >
                                {t("photos_count", {
                                    count: collectionSummary.fileCount,
                                })}
                                {visibleDate && ` · ${visibleDate}`}
                            </Typography>
                        </Box>
                        <IconButton
                            onClick={onClose}
                            size="small"
                            sx={{
                                color: "text.secondary",
                                bgcolor: "fill.faint",
                                "&:hover": { bgcolor: "fill.muted" },
                            }}
                        >
                            <CloseIcon />
                        </IconButton>
                    </Box>
                </StickyDateHeader>
                <FileListContainer>
                    {visibleFiles.length > 0 ? (
                        <FileListWithViewer
                            files={visibleFiles}
                            user={user}
                            favoriteFileIDs={favoriteFileIDs}
                            pendingFavoriteUpdates={pendingFavoriteUpdates}
                            pendingVisibilityUpdates={pendingVisibilityUpdates}
                            onToggleFavorite={onToggleFavorite}
                            onFileVisibilityUpdate={onFileVisibilityUpdate}
                            onRemotePull={onRemotePull}
                            onVisualFeedback={onVisualFeedback}
                            onAddSaveGroup={onAddSaveGroup}
                            onMarkTempDeleted={onMarkTempDeleted}
                            onAddFileToCollection={onAddFileToCollection}
                            onRemoteFilesPull={onRemoteFilesPull}
                            fileNormalCollectionIDs={fileNormalCollectionIDs}
                            collectionNameByID={collectionNameByID}
                            onSelectCollection={onSelectCollection}
                            onSelectPerson={onSelectPerson}
                            emailByUserID={emailByUserID}
                            enableImageEditing={false}
                            enableDownload={true}
                            activeCollectionID={collectionSummary.id}
                            selected={emptySelected}
                            setSelected={noOpSetSelected}
                            onSetOpenFileViewer={onSetOpenFileViewer}
                            listBorderRadius={isMobile ? "0" : "0 0 32px 32px"}
                            header={coverHeader}
                            onScroll={setScrollOffset}
                            onVisibleDateChange={setCurrentDate}
                        />
                    ) : isVisiblePhotosUpdating ? null : (
                        <EmptyStateContainer>
                            {shouldShowCover && (
                                <MapCover
                                    name={collectionSummary.name}
                                    coverImageUrl={coverImageUrl}
                                    totalCount={collectionSummary.fileCount}
                                    onClose={onClose}
                                />
                            )}
                            <EmptyStateMessage>
                                <Typography
                                    variant="body"
                                    sx={{ fontWeight: 600 }}
                                >
                                    {t("no_photos_found_here")}
                                </Typography>
                                <Typography
                                    variant="small"
                                    sx={{ color: "text.secondary" }}
                                >
                                    {t("zoom_out_to_see_photos")}
                                </Typography>
                            </EmptyStateMessage>
                        </EmptyStateContainer>
                    )}
                </FileListContainer>
            </SidebarContainer>
            {isDarkMode && <SidebarGradient />}
        </SidebarWrapper>
    );
}

interface MapCanvasProps {
    mapComponents: MapComponents;
    mapCenter: [number, number];
    mapIndex: MapIndex;
    thumbByFileID: Map<number, string>;
    onVisibleFileIDsChange: (fileIDs: number[]) => void;
    onVisiblePhotosLoadingChange: (loading: boolean) => void;
    onPrefetchThumbnails: (fileIDs: number[]) => void;
}

const openStreetMapAttribution =
    '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">OpenStreetMap</a> contributors';

const leafletAttributionPrefix =
    '<a href="https://leafletjs.com" target="_blank" rel="noopener noreferrer">Leaflet</a>';

const MapCanvas = React.memo(function MapCanvas({
    mapComponents,
    mapCenter,
    mapIndex,
    thumbByFileID,
    onVisibleFileIDsChange,
    onVisiblePhotosLoadingChange,
    onPrefetchThumbnails,
}: MapCanvasProps) {
    const { MapContainer, TileLayer, Marker, useMap } = mapComponents;

    return (
        <MapCanvasContainer>
            <MapContainer
                center={mapCenter}
                zoom={DEFAULT_MAP_ZOOM}
                scrollWheelZoom
                zoomControl={false}
                style={{ width: "100%", height: "100%" }}
            >
                <TileLayer
                    attribution={openStreetMapAttribution}
                    url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
                    maxZoom={MAX_MAP_ZOOM}
                    updateWhenZooming
                />
                <MapControls useMap={useMap} />
                <MapClusters
                    useMap={useMap}
                    mapIndex={mapIndex}
                    thumbByFileID={thumbByFileID}
                    onVisibleFileIDsChange={onVisibleFileIDsChange}
                    onVisiblePhotosLoadingChange={onVisiblePhotosLoadingChange}
                    onPrefetchThumbnails={onPrefetchThumbnails}
                    Marker={Marker}
                />
            </MapContainer>
        </MapCanvasContainer>
    );
});

interface MapControlsProps {
    useMap: typeof import("react-leaflet").useMap;
}

const MapControls = React.memo(function MapControls({
    useMap,
}: MapControlsProps) {
    const map = useMap();

    useEffect(() => {
        map.attributionControl.setPrefix(leafletAttributionPrefix);
    }, [map]);

    const handleOpenInMaps = useCallback(() => {
        const center = map.getCenter();
        const url = `https://www.google.com/maps?q=${center.lat},${center.lng}&z=${map.getZoom()}`;
        window.open(url, "_blank", "noopener,noreferrer");
    }, [map]);

    const handleZoomIn = useCallback(() => map.zoomIn(), [map]);
    const handleZoomOut = useCallback(() => map.zoomOut(), [map]);

    return (
        <>
            <Stack
                spacing={1}
                sx={(theme) => ({
                    position: "absolute",
                    left: 24,
                    top: 24,
                    zIndex: 1000,
                    [theme.breakpoints.up("md")]: {
                        left: "auto",
                        top: "auto",
                        right: 24,
                        bottom: 48,
                    },
                })}
            >
                <FloatingIconButton onClick={handleZoomIn}>
                    <AddIcon />
                </FloatingIconButton>
                <FloatingIconButton onClick={handleZoomOut}>
                    <RemoveIcon />
                </FloatingIconButton>
                <FloatingIconButton
                    onClick={handleOpenInMaps}
                    sx={(theme) => ({
                        display: "none",
                        [theme.breakpoints.up("md")]: { display: "flex" },
                    })}
                >
                    <LocationOnIcon />
                </FloatingIconButton>
            </Stack>

            <FloatingIconButton
                onClick={handleOpenInMaps}
                sx={(theme) => ({
                    position: "absolute",
                    right: 24,
                    top: 24,
                    zIndex: 1000,
                    [theme.breakpoints.up("md")]: { display: "none" },
                })}
            >
                <LocationOnIcon />
            </FloatingIconButton>
        </>
    );
});

const isClusterFeature = (feature: MapFeature): feature is MapClusterFeature =>
    feature.properties.cluster === true;

interface MapClustersProps {
    useMap: typeof import("react-leaflet").useMap;
    mapIndex: MapIndex;
    thumbByFileID: Map<number, string>;
    onVisibleFileIDsChange: (fileIDs: number[]) => void;
    onVisiblePhotosLoadingChange: (loading: boolean) => void;
    onPrefetchThumbnails: (fileIDs: number[]) => void;
    Marker: typeof import("react-leaflet").Marker;
}

const MapClusters = React.memo(function MapClusters({
    useMap,
    mapIndex,
    thumbByFileID,
    onVisibleFileIDsChange,
    onVisiblePhotosLoadingChange,
    onPrefetchThumbnails,
    Marker,
}: MapClustersProps) {
    const map = useMap();
    const [featureState, setFeatureState] = useState<{
        mapIndex: MapIndex;
        features: MapFeature[];
    }>(() => ({ mapIndex, features: [] }));

    const features =
        featureState.mapIndex === mapIndex ? featureState.features : [];
    const previousVisibleIdsRef = useRef<Set<number>>(new Set());
    const visibleRequestIdRef = useRef(0);
    const iconCacheRef = useRef(
        new Map<string, ReturnType<typeof createMarkerIcon>>(),
    );

    const updateVisibleLeaves = useCallback(
        async (
            requestId: number,
            clusters: MapFeature[],
            bounds: { contains: (latlng: [number, number]) => boolean },
        ) => {
            if (requestId !== visibleRequestIdRef.current) return;
            onVisiblePhotosLoadingChange(true);

            const inBounds = (lat: number, lng: number) =>
                bounds.contains([lat, lng]);

            const leaves: MapPointFeature[] = [];
            let processedClusters = 0;

            for (const feature of clusters) {
                if (requestId !== visibleRequestIdRef.current) return;

                if (isClusterFeature(feature)) {
                    const clusterProps = feature.properties;
                    const totalLeaves = clusterProps.point_count;
                    const batchSize = 1000;
                    for (
                        let offset = 0;
                        offset < totalLeaves;
                        offset += batchSize
                    ) {
                        if (requestId !== visibleRequestIdRef.current) return;
                        const clusterLeaves = mapIndex.getLeaves(
                            clusterProps.cluster_id,
                            batchSize,
                            offset,
                        );
                        clusterLeaves.forEach((leaf) => {
                            const [lng, lat] = leaf.geometry.coordinates;
                            if (inBounds(lat, lng)) {
                                leaves.push(leaf);
                            }
                        });
                        await new Promise((resolve) => setTimeout(resolve, 0));
                    }
                    processedClusters += 1;
                    if (processedClusters % 5 === 0) {
                        await new Promise((resolve) => setTimeout(resolve, 0));
                    }
                } else {
                    const [lng, lat] = feature.geometry.coordinates;
                    if (inBounds(lat, lng)) {
                        leaves.push(feature);
                    }
                }
            }

            if (requestId !== visibleRequestIdRef.current) return;

            leaves.sort(
                (a, b) => b.properties.timestamp - a.properties.timestamp,
            );

            const visibleIds = new Set(
                leaves.map((leaf) => leaf.properties.fileId),
            );
            const previousIds = previousVisibleIdsRef.current;
            const idsChanged =
                visibleIds.size !== previousIds.size ||
                [...visibleIds].some((id) => !previousIds.has(id));

            if (idsChanged) {
                previousVisibleIdsRef.current = visibleIds;
                startTransition(() => {
                    onVisibleFileIDsChange(
                        leaves.map((leaf) => leaf.properties.fileId),
                    );
                });
            }

            if (requestId === visibleRequestIdRef.current) {
                onVisiblePhotosLoadingChange(false);
            }
        },
        [mapIndex, onVisibleFileIDsChange, onVisiblePhotosLoadingChange],
    );

    const updateClusters = useCallback(() => {
        const bounds = map.getBounds();
        const zoom = Math.round(map.getZoom());
        const bbox: [number, number, number, number] = [
            bounds.getWest(),
            bounds.getSouth(),
            bounds.getEast(),
            bounds.getNorth(),
        ];

        const nextZoom = Math.min(zoom + 1, MAX_MAP_ZOOM);
        const clusters = mapIndex.getClusters(bbox, zoom);
        setFeatureState({ mapIndex, features: clusters });

        const requestId = ++visibleRequestIdRef.current;
        void updateVisibleLeaves(requestId, clusters, bounds);

        const prefetchBounds = bounds.pad(PREFETCH_BOUNDS_PADDING);
        const prefetchBbox: [number, number, number, number] = [
            prefetchBounds.getWest(),
            prefetchBounds.getSouth(),
            prefetchBounds.getEast(),
            prefetchBounds.getNorth(),
        ];

        const prefetchTargets = new Set<number>();
        const collectTargets = (items: MapFeature[]) => {
            items.forEach((feature) => {
                if (isClusterFeature(feature)) {
                    prefetchTargets.add(feature.properties.latestFileId);
                } else {
                    prefetchTargets.add(feature.properties.fileId);
                }
            });
        };

        collectTargets(clusters);
        collectTargets(mapIndex.getClusters(prefetchBbox, nextZoom));

        onPrefetchThumbnails(Array.from(prefetchTargets));
    }, [map, mapIndex, onPrefetchThumbnails, updateVisibleLeaves]);

    useEffect(() => {
        iconCacheRef.current.clear();
        previousVisibleIdsRef.current = new Set();
        visibleRequestIdRef.current += 1;
    }, [mapIndex]);

    useEffect(() => {
        updateClusters();
    }, [updateClusters]);

    useEffect(() => {
        map.on("moveend", updateClusters);
        map.on("zoomend", updateClusters);
        return () => {
            map.off("moveend", updateClusters);
            map.off("zoomend", updateClusters);
        };
    }, [map, updateClusters]);

    const currentZoom = Math.round(map.getZoom());

    return (
        <>
            {features.map((feature) => {
                const [lng, lat] = feature.geometry.coordinates;
                const isCluster = isClusterFeature(feature);

                if (isCluster) {
                    const clusterProps = feature.properties;
                    const clusterId = clusterProps.cluster_id;
                    const count = clusterProps.point_count;
                    const expansionZoom = Math.min(
                        mapIndex.getClusterExpansionZoom(clusterId),
                        MAX_MAP_ZOOM,
                    );
                    const isInteractive = expansionZoom > currentZoom;
                    const thumb =
                        thumbByFileID.get(clusterProps.latestFileId) ?? "";
                    const cacheKey = `cluster-${clusterId}-${count}-${thumb}-${isInteractive ? "i" : "n"}`;
                    let icon = iconCacheRef.current.get(cacheKey);
                    if (!icon) {
                        icon = createMarkerIcon(thumb, count, isInteractive);
                        if (icon) {
                            iconCacheRef.current.set(cacheKey, icon);
                        }
                    }
                    return (
                        <Marker
                            key={`cluster-${clusterId}`}
                            position={[lat, lng]}
                            icon={icon ?? undefined}
                            eventHandlers={
                                isInteractive
                                    ? {
                                          click: () =>
                                              map.setView(
                                                  [lat, lng],
                                                  expansionZoom,
                                                  { animate: true },
                                              ),
                                      }
                                    : undefined
                            }
                        />
                    );
                }

                const fileId = feature.properties.fileId;
                const thumb = thumbByFileID.get(fileId) ?? "";
                const cacheKey = `point-${fileId}-${thumb}`;
                let icon = iconCacheRef.current.get(cacheKey);
                if (!icon) {
                    icon = createMarkerIcon(thumb);
                    if (icon) {
                        iconCacheRef.current.set(cacheKey, icon);
                    }
                }
                return (
                    <Marker
                        key={`point-${fileId}`}
                        position={[lat, lng]}
                        icon={icon ?? undefined}
                    />
                );
            })}
        </>
    );
});

const FloatingIconButton: React.FC<IconButtonProps> = ({ sx, ...props }) => {
    const baseSx = {
        bgcolor: "background.paper",
        boxShadow: 4,
        width: 48,
        height: 48,
        borderRadius: "16px",
        transition: "transform 0.2s ease-out",
        "&:hover": { bgcolor: "background.paper", transform: "scale(1.05)" },
    };

    const mergedSx =
        sx == null
            ? baseSx
            : Array.isArray(sx)
              ? // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
                [baseSx, ...sx]
              : [baseSx, sx];

    return <IconButton {...props} sx={mergedSx} />;
};

interface CenteredBoxProps extends React.PropsWithChildren {
    onClose?: () => void;
    closeLabel?: string;
}

function CenteredBox({ children, onClose, closeLabel }: CenteredBoxProps) {
    return (
        <CenteredBoxContainer>
            {onClose && (
                <IconButton
                    aria-label={closeLabel ?? "Close"}
                    onClick={onClose}
                    sx={{ position: "absolute", top: 16, right: 16 }}
                >
                    <CloseIcon />
                </IconButton>
            )}
            {children}
        </CenteredBoxContainer>
    );
}

interface MapCoverProps {
    name: string;
    coverImageUrl: string | undefined;
    totalCount: number;
    onClose: () => void;
}

const MapCover = React.memo(function MapCover({
    name,
    coverImageUrl,
    totalCount,
    onClose,
}: MapCoverProps) {
    return (
        <CoverContainer>
            <CoverImageContainer>
                <img
                    src={coverImageUrl}
                    alt="Cover"
                    style={{
                        position: "absolute",
                        inset: 0,
                        width: "100%",
                        height: "100%",
                        objectFit: "cover",
                        objectPosition: "Center",
                    }}
                />
                <CoverGradientOverlay />

                <CoverCloseButton aria-label="Close" onClick={onClose}>
                    <CloseIcon sx={{ fontSize: 20 }} />
                </CoverCloseButton>

                <CoverContentContainer>
                    <CoverTitle>{name}</CoverTitle>
                    <CoverSubtitle>
                        {t("photos_count", { count: totalCount })}
                    </CoverSubtitle>
                </CoverContentContainer>
            </CoverImageContainer>
        </CoverContainer>
    );
});

const MapCanvasContainer = styled(Box)(({ theme }) => ({
    width: "100%",
    height: "100%",
    [theme.breakpoints.down("md")]: {
        "& .leaflet-bottom.leaflet-right": { bottom: MOBILE_SIDEBAR_HEIGHT },
    },
}));

const CoverContainer = styled(Box)(({ theme }) => ({
    width: "100%",
    flexShrink: 0,
    paddingTop: "16px",
    paddingBottom: "16px",
    [theme.breakpoints.down("md")]: {
        padding: "8px",
        paddingTop: "20px",
        paddingBottom: "12px",
    },
}));

const CoverImageContainer = styled(Box)(({ theme }) => ({
    height: `${COVER_IMAGE_HEIGHT}px`,
    position: "relative",
    overflow: "hidden",
    backgroundColor: "#333",
    borderRadius: "36px 36px 24px 24px",
    marginTop: "2px",
    [theme.breakpoints.down("md")]: { borderRadius: "20px" },
}));

const CoverGradientOverlay = styled(Box)({
    position: "absolute",
    inset: 0,
    background:
        "linear-gradient(to bottom, rgba(0,0,0,0.4), transparent 35%, transparent 60%, rgba(0,0,0,0.75))",
});

const CoverCloseButton = styled(IconButton)({
    position: "absolute",
    top: "12px",
    right: "12px",
    color: "white",
    backgroundColor: "rgba(0, 0, 0, 0.3)",
    "&:hover": { backgroundColor: "rgba(0, 0, 0, 0.5)" },
});

const CoverContentContainer = styled(Box)({
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    padding: "24px",
    paddingLeft: "18px",
    color: "white",
});

const CoverTitle = styled(Typography)({
    fontSize: "22px",
    fontWeight: "bold",
    marginBottom: "6px",
    lineHeight: 1.2,
});

const CoverSubtitle = styled(Typography)({
    color: "rgba(255, 255, 255, 0.85)",
    fontSize: "14px",
    fontWeight: "500",
});

const SidebarWrapper = styled(Box)(({ theme }) => ({
    position: "absolute",
    left: 0,
    top: "auto",
    bottom: 0,
    right: 0,
    width: "100%",
    height: MOBILE_SIDEBAR_HEIGHT,
    zIndex: 1000,
    [theme.breakpoints.up("md")]: {
        left: 16,
        top: 16,
        bottom: 16,
        right: "auto",
        height: "auto",
        width: "30%",
        maxWidth: "600px",
        minWidth: "450px",
    },
}));

const SidebarContainer = styled(Box)(({ theme }) => ({
    position: "relative",
    width: "100%",
    height: "100%",
    backgroundColor: theme.vars.palette.background.paper,
    boxShadow: theme.shadows[10],
    display: "flex",
    flexDirection: "column",
    overflow: "hidden",
    borderRadius: "24px 24px 0 0",
    [theme.breakpoints.up("md")]: { borderRadius: "48px" },
}));

const SidebarGradient = styled(Box)(({ theme }) => ({
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    height: "80px",
    background:
        "linear-gradient(to top, rgba(0,0,0,1) 0%, rgba(0,0,0,0.65) 2%, rgba(0,0,0,0) 100%)",
    pointerEvents: "none",
    [theme.breakpoints.up("md")]: {
        height: "150px",
        borderRadius: "0 0 48px 48px",
    },
}));

const FileListContainer = styled(Box)(({ theme }) => ({
    flex: 1,
    minHeight: 0,
    position: "relative",
    display: "flex",
    flexDirection: "column",
    paddingLeft: "8px",
    paddingRight: "8px",
    paddingBottom: "calc(env(safe-area-inset-bottom, 0px) + 16px)",
    [theme.breakpoints.up("md")]: {
        paddingLeft: "16px",
        paddingRight: "16px",
        paddingBottom: "18px",
    },
}));

const StickyDateHeader = styled(Box)<{
    visible: boolean;
    variant: "overlay" | "static";
}>(({ theme, visible, variant }) => {
    const isStatic = variant === "static";
    return {
        position: isStatic ? "relative" : "absolute",
        top: 0,
        left: 0,
        right: 0,
        zIndex: 10,
        backgroundColor: theme.vars.palette.background.paper,
        padding: "28px 24px 24px 24px",
        borderBottom: `1px solid ${theme.vars.palette.divider}`,
        opacity: isStatic || visible ? 1 : 0,
        transform: isStatic || visible ? "translateY(0)" : "translateY(-10px)",
        pointerEvents: isStatic || visible ? "auto" : "none",
        transition: isStatic
            ? "none"
            : "opacity 0.25s ease-out, transform 0.25s ease-out",
        [theme.breakpoints.down("md")]: { padding: "24px 20px 20px 20px" },
    };
});

const CenteredBoxContainer = styled(Box)({
    width: "100%",
    height: "100%",
    minHeight: "420px",
    position: "relative",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
    flexDirection: "column",
    textAlign: "center",
});

const EmptyStateContainer = styled(Box)(({ theme }) => ({
    minHeight: "100%",
    position: "relative",
    display: "flex",
    flexDirection: "column",
    paddingBottom: theme.spacing(4),
    color: theme.vars.palette.text.secondary,
    overflow: "auto",
}));

const EmptyStateMessage = styled(Box)(({ theme }) => ({
    position: "absolute",
    top: "50%",
    left: "50%",
    transform: "translate(-50%, -50%)",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    textAlign: "center",
    gap: theme.spacing(1),
}));
