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
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import {
    fileCreationPhotoSortTime,
    fileLocation,
    ItemVisibility,
    metadataHash,
} from "ente-media/file-metadata";
import type { RemotePullOpts } from "ente-new/photos/components/gallery";
import {
    addToFavoritesCollection,
    removeFromFavoritesCollection,
} from "ente-new/photos/services/collection";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { updateFilesVisibility } from "ente-new/photos/services/file";
import {
    savedCollectionFiles,
    savedCollections,
} from "ente-new/photos/services/photos-fdb";
import { t } from "i18next";
import "leaflet/dist/leaflet.css";
import type { Dispatch, SetStateAction } from "react";
import React, {
    startTransition,
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";
import Supercluster from "supercluster";
import type { FileListWithViewerProps } from "../FileListWithViewer";
import { FileListWithViewer } from "../FileListWithViewer";

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
            | "mapFileSource"
            | "emailByUserID"
        > {
    collectionSummary: CollectionSummary;
    activeCollection: Collection | undefined;
    files: EnteFile[];
    onRemotePull?: (opts?: RemotePullOpts) => Promise<void>;
}

// Describes all map-related state used in the dialog:
// - mapCenter: current map center, typically derived from the latest file with location
// - mapIndex/mapPoints/latestFileId: spatial index and its source points, plus the newest file id
// - filesByID/thumbByFileID: cached file metadata and lazily-fetched thumbnails
// - isLoading/error: loading/error flags for map data fetches

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

/**
 * When files are being opened from the the Sidebar, there is ablity to add them as favoriate,
 * archive them or unarchieve them and this interface is for facilitating that. Where the favoruteFileIds
 * hols the existing favorites, pending holds the ones which are in progress for respective ones
 */

interface FavoritesState {
    favoriteFileIDs: Set<number>;
    pendingFavoriteUpdates: Set<number>;
    pendingVisibilityUpdates: Set<number>;
}

/**
 * Extension of MapDataState that adds mutation functions for map data management.
 * - removeFiles: Removes files from the map index when deleted from FileListWithViewer
 * - updateFileVisibility: Updates file visibility state and removes hidden files from the map
 * - queueThumbnailFetch: Batches and fetches thumbnails on demand for visible files
 */

interface MapDataResult extends MapDataState {
    removeFiles: (fileIDs: number[]) => void;
    updateFileVisibility: (file: EnteFile, visibility: ItemVisibility) => void;
    queueThumbnailFetch: (fileIDs: number[]) => void;
}

/**
 * Dynamically loaded map components to avoid SSR issues with Leaflet. Normal imports actually caused
 * the app to break in some instances, thus dynamically loading them instead.
 * Loaded lazily in useMapComponents() hook when the dialog opens to ensure window exists.
 */
interface MapComponents {
    MapContainer: typeof import("react-leaflet").MapContainer;
    TileLayer: typeof import("react-leaflet").TileLayer;
    Marker: typeof import("react-leaflet").Marker;
    useMap: typeof import("react-leaflet").useMap;
}

/**
 * Represents a geotagged photo point stored in the map spatial index.
 * Each point corresponds to a photo with location metadata.
 * - fileId: Unique identifier for the photo file
 * - lat: Latitude coordinate of the photo location
 * - lng: Longitude coordinate of the photo location
 * - timestamp: Millisecond sort key in the local photo timeline.
 */

interface MapIndexPoint {
    fileId: number;
    lat: number;
    lng: number;
    timestamp: number;
}

interface MapPhotoPoint {
    lat: number;
    lng: number;
    name: string;
    country: string;
    image: string;
    fileId: number;
}

/**
 * Along with the GeoTagged photos we are also storing a metadata, which changes
 * only when there is change in the stored values, to prevent this from updating
 * each time when there is change. Currently fileCount and updationTime are the
 * two metrics kept to analyse this change.
 */

/**
 * The small payload we attach to a point: fileId points to the photo, and
 * timestamp keeps enough local-photo timeline context for sorting or choosing
 * the freshest item in a cluster.
 */
interface MapPointProperties {
    fileId: number;
    timestamp: number;
}

/**
 * A GeoJSON feature for a single photo point. GeoJSON is the small, common shape most map
 * libraries expect for geographic data, so we stick with it even when we only need a
 * couple of fields. type stays "Feature" because that is the GeoJSON spec's envelope for
 * real-world points; it does not change our logic, but it keeps the data recognizable to
 * tooling like Supercluster. properties carry the fileId and timestamp (and keep cluster
 * as false), and geometry stores the point in [lng, lat] order for map libs.
 */
interface MapPointFeature {
    type: "Feature";
    properties: MapPointProperties & { cluster?: false };
    geometry: { type: "Point"; coordinates: [number, number] };
}

/**
 * Summary info for a cluster: latestTimestamp and latestFileId keep track of the freshest
 * photo inside the cluster so we can choose a representative cover.
 */
interface MapClusterProperties {
    latestTimestamp: number;
    latestFileId: number;
}

/**
 * A GeoJSON feature that represents a cluster instead of a single point. properties mark
 * it as a cluster, carry cluster_id for expansion, point_count for the raw size, and
 * point_count_abbreviated for a compact label, while geometry still gives the centroid.
 */
interface MapClusterFeature {
    type: "Feature";
    properties: MapClusterProperties & {
        cluster: true;
        cluster_id: number;
        point_count: number;
        point_count_abbreviated?: number | string;
    };
    geometry: { type: "Point"; coordinates: [number, number] };
}

/**
 * Convenience union so callers can handle clusters and single points together.
 */
type MapFeature = MapClusterFeature | MapPointFeature;

/**
 * The small contract we rely on from Supercluster: load ingests points, getClusters
 * returns mixed clusters/points for bounds and zoom, getLeaves expands a cluster into
 * its points, and getClusterExpansionZoom tells us how far to zoom to break it apart.
 */
interface MapIndex {
    load(points: MapPointFeature[]): MapIndex;
    getClusters(
        bbox: [number, number, number, number],
        zoom: number,
    ): MapFeature[];
    getLeaves(
        clusterId: number,
        limit: number,
        offset: number,
    ): MapPointFeature[];
    getClusterExpansionZoom(clusterId: number): number;
}

/**
 * Tuning knobs for building the index: radius controls cluster size in pixels, maxZoom
 * caps clustering depth, map shapes point data into the cluster properties we track,
 * and reduce merges those properties as clusters grow.
 */
interface MapClusterOptions {
    radius?: number;
    maxZoom?: number;
    map?: (props: MapPointProperties) => MapClusterProperties;
    reduce?: (
        accumulated: MapClusterProperties,
        props: MapClusterProperties,
    ) => void;
}

type SuperclusterConstructor = new (options?: MapClusterOptions) => MapIndex;

//OpenStreetMap only supports clustering till this zoom level and this tell the supercluster what the max limit is for the zoom.
const MAX_MAP_ZOOM = 19;
const DEFAULT_MAP_ZOOM = 10;
//Instead of loading just the tiles which are in view, we're actually loading the 15% of the surrounding zone as well for smoother experience.
//Leaflet LatLngBounds.pad expects a ratio (0.15 = 15%).
const PREFETCH_BOUNDS_PADDING = 0.15;
//This count controls how many thumbnails are fetched in each batch when loading images for the markers
const THUMBNAIL_BATCH_SIZE = 40;

/**
 * This is the first hook which is being loaded when the CollectionMapDialog is mounted
 * Dynamically loads map-related React components (Leaflet) to avoid SSR issues
 * Responsibility: Lazy load map dependencies only when needed (window must exist)
 */
function useMapComponents() {
    const [mapComponents, setMapComponents] = useState<MapComponents | null>(
        null,
    );

    useEffect(() => {
        // Only load on client-side where window exists, and updates the state with the components.
        if (typeof window === "undefined") return;

        void import("react-leaflet")
            .then((leaflet) =>
                setMapComponents({
                    MapContainer: leaflet.MapContainer,
                    TileLayer: leaflet.TileLayer,
                    Marker: leaflet.Marker,
                    useMap: leaflet.useMap,
                }),
            )
            .catch((e: unknown) => {
                console.error("Failed to load map components", e);
            });
    }, []);

    return mapComponents;
}

/**
 * Retrieves the current authenticated user data and throws error if the user is not loggedIn.
 * Responsibility: Provide user context for favorite/visibility operations
 */
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

const emptyFileIDs = new Set<number>();

/**
 *
 * @param collectionSummaryType
 * @returns Checks if the current active collection is All or userFavorites
 * if so then we return true.
 *
 * This function is relevant because in All and Favorites album we have to handle
 * the shared favorite files seperately.
 */
const shouldUseLocationAwareMapRepresentatives = (
    collectionSummaryType: CollectionSummary["type"],
) => collectionSummaryType == "all" || collectionSummaryType == "userFavorites";

/**
 *
 * @param file The file for which we are checking whether the file
 * can be used as a MapEquivalent.
 *
 * @param hiddenFileIDs The list of files which are hidden by the user
 * @param archivedFileIDs The list of files which are archieved by the user
 * @param tempDeletedFileIDs The list of files which are just deleted.
 * @param tempHiddenFileIDs The list of the files which are just hidden.
 *
 * the tempDeletedFileIDs and the tempHiddenFileIDs hold the IDs of the files
 * on which the action was just performed, and the remotePull hasn't happened yet
 * so without these variables, a just-hidden/deleted file might still show up
 * as an MapEquivalent file.
 * @returns
 */
const canUseFileAsMapEquivalent = (
    file: EnteFile,
    hiddenFileIDs: Set<number>,
    archivedFileIDs: Set<number>,
    tempDeletedFileIDs: Set<number>,
    tempHiddenFileIDs: Set<number>,
) => {
    // If the file is hidden, deleted or archieved then returning false.
    if (tempDeletedFileIDs.has(file.id)) return false;
    if (hiddenFileIDs.has(file.id)) return false;
    if (tempHiddenFileIDs.has(file.id)) return false;
    if (archivedFileIDs.has(file.id)) return false;

    // Confirming that the file's visiblity is set to visible/undefined.
    const visibility = file.magicMetadata?.data.visibility;
    return visibility === undefined || visibility === ItemVisibility.visible;
};

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
    // If there is no loggedIn user or if the album is not
    // All or Favorites then returning the files which we got
    // from the gallery itself without any additional
    // shared-favorite swapping or handling.
    if (
        !currentUserID ||
        !shouldUseLocationAwareMapRepresentatives(collectionSummaryType)
    ) {
        return files;
    }

    const filesByHashAndType = new Map<string, EnteFile[]>();
    for (const file of collectionFiles) {
        // If a file doesn't statisfy the requirements of showing
        // up as a MapEquivalent then skipping it.
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

        // If the file can be shown in the map getting the FileHashAndTypeKey
        const key = favoriteFileHashAndTypeKey(file);

        if (!key) continue;

        // Grouping the same files using their FileHashAndTypeKey as the key.
        const matchingFiles = filesByHashAndType.get(key);
        if (matchingFiles) {
            matchingFiles.push(file);
        } else {
            filesByHashAndType.set(key, [file]);
        }
    }

    const mapFiles: EnteFile[] = [];
    const mapFileIDs = new Set<number>();

    // Looping through the files which we got passed down from the gallery.
    for (const file of files) {
        const key = favoriteFileHashAndTypeKey(file);
        const equivalentFiles = key ? filesByHashAndType.get(key) : undefined;

        // if there is no equivalentFiles it means that the file has only one copy
        // which is the original copy so keep it that.
        if (!equivalentFiles) {
            addUniqueMapFile(mapFiles, mapFileIDs, file);
            continue;
        }

        // If we are in the All view, we check if any of the equivalentFiles
        // are favorited, if not then we pass the original file to the addUniqueMapFile
        if (
            collectionSummaryType == "all" &&
            !equivalentFiles.some((equivalentFile) =>
                favoriteFileIDs.has(equivalentFile.id),
            )
        ) {
            addUniqueMapFile(mapFiles, mapFileIDs, file);
            continue;
        }

        // If we get here, the file has equivalentFiles and atleast one
        // of them is favorited. So we split the equivalent files according
        // to their ownership.

        const ownedFiles = equivalentFiles.filter(
            (equivalentFile) => equivalentFile.ownerID == currentUserID,
        );
        const sharedFiles = equivalentFiles.filter(
            (equivalentFile) => equivalentFile.ownerID != currentUserID,
        );

        /**
         * If there is not both an owned and shared side, it keeps the original file.
         * The special logic only matters when the same underlying media exists as both an owned copy and a shared copy.
         */
        if (!ownedFiles.length || !sharedFiles.length) {
            addUniqueMapFile(mapFiles, mapFileIDs, file);
            continue;
        }

        const ownedFilesWithLocation = ownedFiles.filter(fileLocation);
        const sharedFilesWithLocation = sharedFiles.filter(fileLocation);

        if (ownedFilesWithLocation.length && sharedFilesWithLocation.length) {
            // both owned and shared have location: add shared-with-location, then owned-with-location
            for (const sharedFile of sharedFilesWithLocation) {
                addUniqueMapFile(mapFiles, mapFileIDs, sharedFile);
            }
            for (const ownedFile of ownedFilesWithLocation) {
                addUniqueMapFile(mapFiles, mapFileIDs, ownedFile);
            }
        } else if (sharedFilesWithLocation.length) {
            // only shared has location: add shared-with-location
            for (const sharedFile of sharedFilesWithLocation) {
                addUniqueMapFile(mapFiles, mapFileIDs, sharedFile);
            }
        } else if (ownedFilesWithLocation.length) {
            // only owned has location: add owned-with-location
            for (const ownedFile of ownedFilesWithLocation) {
                addUniqueMapFile(mapFiles, mapFileIDs, ownedFile);
            }
        } else {
            // neither has location: keep the original file
            addUniqueMapFile(mapFiles, mapFileIDs, file);
        }
    }

    return mapFiles;
};

const deriveFavoriteFileIDs = (
    userID: number,
    favoritesCollectionID: number,
    collectionFiles: EnteFile[],
) => {
    const favoriteFiles = collectionFiles.filter(
        (file) => file.collectionID == favoritesCollectionID,
    );
    const favoriteFileIDs = new Set(favoriteFiles.map((file) => file.id));
    const favoriteFileHashAndTypeKeys = new Set(
        favoriteFiles.flatMap((file) => {
            const key = favoriteFileHashAndTypeKey(file);
            return key ? [key] : [];
        }),
    );

    for (const file of collectionFiles) {
        if (file.ownerID == userID) continue;

        const key = favoriteFileHashAndTypeKey(file);
        if (key && favoriteFileHashAndTypeKeys.has(key)) {
            favoriteFileIDs.add(file.id);
        }
    }

    return favoriteFileIDs;
};

/**
 *
 * @param files
 * @returns points, latestFileId
 *
 * This function create the inital mapIndexPoint any collection.
 * It's later this points
 * that is being given to the supercluster for the mapping and indexing.
 *
 * This function loops over the entire files which is suspect is not EFFICENT
 * but currently it loads about 1,00,000 images seamlessly which is far better
 * than the earlier implementation we had.
 */
const buildMapIndexPoints = async (files: EnteFile[]) => {
    const points: MapIndexPoint[] = [];
    let latestTimestamp = -1;
    let latestFileId: number | undefined;

    //looping over each file to extract their time and location to create the point
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

        /**
         * This pauses the event loop briefly, so the main thead is not blocked if there are mutliple so many files.
         * This doesn't change the complexisty of this loop, just keep the thread responsive for UI updates, input and rendering.
         */

        if (index > 0 && index % 5000 === 0) {
            await new Promise((resolve) => setTimeout(resolve, 0));
        }
    }

    return { points, latestFileId };
};

/**
 *
 * @param points
 * @returns a SuperCluster Spatial Index, using which we can retrive (1)the clusters/points for a particular bbox + zoom level
 * (2) all leaves under a cluster. (3) the maximum zoom for a particular cluster
 *
 * This function converts every MapIndexPoint to a GeoJSON Feature(required for rendering
 * using supercluster)[type MapPointFeature]. NOTE this index is not persisted.
 */
const buildClusterIndex = (points: MapIndexPoint[]): MapIndex => {
    /**
     *   - For every point we load, Supercluster calls map(props) once to decide what
     *      cluster metadata that point contributes.
     *
     *   - When multiple points are to begrouped into a cluster, Supercluster repeatedly calls
     *      reduce(accumulated, props) to merge those per‑point metadata objects into a single cluster summary.
     */

    const options: MapClusterOptions = {
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
    };

    const SuperclusterCtor = Supercluster as unknown as SuperclusterConstructor;
    const index = new SuperclusterCtor(options);

    // converting MapIndexPoint -> MapPointFeature
    const features: MapPointFeature[] = points.map((point) => ({
        type: "Feature" as const,
        properties: { fileId: point.fileId, timestamp: point.timestamp },
        geometry: {
            type: "Point" as const,
            coordinates: [point.lng, point.lat] as [number, number],
        },
    }));

    //builds the spaital cluster hierachy across various zoom level
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

/**
 *
 * @param points
 * @returns MapIndexPoint
 *
 * Though we are computing the latestFile while loadMapData(), sometimes
 * if this latestFile is deleted or archieved by the user then we need
 * to compute a new latestFile, this is the purpose this fn serves.
 */
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

/**
 * Loads and manages map data including index, files, and thumbnails.
 * Responsibility: Fetch collection files, build/persist spatial index, prefetch thumbnails on demand.
 */
function useMapData(
    open: boolean,
    collectionSummary: CollectionSummary,
    files: EnteFile[],
    onGenericError: (e: unknown) => void,
): MapDataResult {
    const [state, setState] = useState<MapDataState>({
        mapCenter: null,
        mapIndex: null,
        mapPoints: [],
        latestFileId: undefined,
        filesByID: new Map(),
        thumbByFileID: new Map(),
        isLoading: false,
        error: null,
    });

    //Ref mirroring the filesByID(state) to prevent the stale closure issue with the queueThumbnailFetch useCallback fn().
    const filesByIDRef = useRef<Map<number, EnteFile>>(new Map());
    //Ref mirroring the thumbByFileID state to prevent the same issue as above
    const thumbsByFileIDRef = useRef<Map<number, string>>(new Map());
    //A work queue with the list of fileIDs waiting to have their thumbs fetched.
    const pendingThumbsRef = useRef<Set<number>>(new Set());
    const isThumbnailWorkerRunningRef = useRef(false);

    // Track which collection we've loaded to avoid unnecessary reloads
    // Include fileCount to detect when collection content changes
    const loadedCollectionRef = useRef<{
        summaryId: number;
        fileCount: number;
        updationTime: number | null;
        files: EnteFile[];
    } | null>(null);

    //Syncing the refs with the state for the stale closure prevention.
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

        /**
         * Loops through the fileIds for which thumbnails are to fetched,
         * and if thumbs are already generated or that fileId doesn't exist
         * then skipping it.
         *
         * Otherwise adding it to the ref for the fetching process
         */
        for (const fileId of fileIDs) {
            if (existingThumbs.has(fileId)) continue;
            if (!filesByID.has(fileId)) continue;
            pending.add(fileId);
        }

        if (isThumbnailWorkerRunningRef.current) return;
        isThumbnailWorkerRunningRef.current = true;

        void (async () => {
            while (pendingThumbsRef.current.size > 0) {
                /**
                 * Since we're fetching in a batched manner, slicing the THUMBNAIL_BATCH_SIZE for fetching and
                 * removing these from the pending list.
                 */

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

                /**
                 * Updating the existing state with the newly fetched thumbnails.
                 */
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

                //To yield control between batches os the UI stays responsive
                await new Promise((resolve) => setTimeout(resolve, 0));
            }

            isThumbnailWorkerRunningRef.current = false;
        })();
    }, []);

    // Clear loaded ref when dialog closes so we reload fresh data next time.
    useEffect(() => {
        if (!open) {
            loadedCollectionRef.current = null;
            pendingThumbsRef.current.clear();
            isThumbnailWorkerRunningRef.current = false;
        }
    }, [open]);

    useEffect(() => {
        if (!open) return;

        // Skip reload if we already have data for this collection with same file count
        const currentSummaryId = collectionSummary.id;
        const currentFileCount = collectionSummary.fileCount;
        const currentUpdationTime = collectionSummary.updationTime ?? null;
        const loaded = loadedCollectionRef.current;

        //preventing reloading of the data if it's already loaded.
        if (
            loaded?.summaryId === currentSummaryId &&
            loaded.fileCount === currentFileCount &&
            loaded.updationTime === currentUpdationTime &&
            loaded.files === files
        ) {
            return;
        }

        const loadMapData = async () => {
            //In this ref we are actually setting a new Set() so clearing that before any compute happens.
            pendingThumbsRef.current.clear();
            setState((prev) => ({ ...prev, isLoading: true, error: null }));

            try {
                const uniqueFiles = uniqueFilesByID(files);

                //Creating a id <- file mapping to drive renders and update the UI, changes to this will result in UI re-renders
                const filesByID = new Map(
                    uniqueFiles.map((file) => [file.id, file]),
                );
                //ref mirrow for using in the useCallbacks
                filesByIDRef.current = filesByID;

                const { points, latestFileId } =
                    await buildMapIndexPoints(uniqueFiles);

                //mapIndex has the SuperCluster Spatial Index
                const mapIndex = buildMapIndex(points);

                const latestPoint =
                    getPointByFileId(points, latestFileId) ?? points[0];

                const mapCenter: [number, number] | null = latestPoint
                    ? [latestPoint.lat, latestPoint.lng]
                    : null;

                setState({
                    filesByID,
                    mapCenter,
                    mapIndex,
                    mapPoints: points,
                    latestFileId,
                    thumbByFileID: new Map(),
                    isLoading: false,
                    error: null,
                });

                // Mark this collection as loaded
                loadedCollectionRef.current = {
                    summaryId: currentSummaryId,
                    fileCount: currentFileCount,
                    updationTime: currentUpdationTime,
                    files,
                };

                const coverId = collectionSummary.coverFile?.id ?? latestFileId;
                if (coverId !== undefined) {
                    queueThumbnailFetch([coverId]);
                }

                return;
            } catch (e) {
                setState((prev) => ({
                    ...prev,
                    isLoading: false,
                    error: t("something_went_wrong"),
                }));
                onGenericError(e);
            } finally {
                // Ensure we never leave the dialog stuck in a loading state
                setState((prev) =>
                    prev.isLoading ? { ...prev, isLoading: false } : prev,
                );
            }
        };

        void loadMapData();
    }, [open, collectionSummary, files, onGenericError, queueThumbnailFetch]);

    /**
     * This function is used to update the map view, after a file has been
     * deleted by the user. The deleted file is removed from the mapPoints
     * and then a new mapIndex is built
     */
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
            //Rebuilding the mapIndex after removing the point from the mapPoints
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

    /**
     * This function is used to update the visiblity of a file from
     * archive to unarchive or vice-versa.
     */
    const updateFileVisibility = useCallback(
        (file: EnteFile, visibility: ItemVisibility) => {
            setState((prev) => {
                //If the file ID is not in the fileByID or the magicMetadata for the file doesn't exist then return prev state
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

                //If the file is not visible then removing it from the mapPoints and creating a new Supercluster Spatial Mapping
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
                    //If the file was previously hidden then adding it back to the existing list.
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

                        //Recomputing the latest file, since there are possiblities of change
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

                //Recomputing the map center in case the latestFile has changed.
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

/**
 * Manages favorite files state and handles favorite/visibility updates
 * Responsibility: Load user's favorites, toggle favorite status, update file visibility
 */
function useFavorites(
    open: boolean,
    user: ReturnType<typeof useCurrentUser>,
    favoriteEquivalenceFiles: EnteFile[],
    syncedFavoriteFileIDs?: Set<number>,
): FavoritesState & {
    handleToggleFavorite: (file: EnteFile) => Promise<void>;
    handleFileVisibilityUpdate: (
        file: EnteFile,
        visibility: ItemVisibility,
    ) => Promise<void>;
} {
    // Set to store the ids of files which are currenly favorited, if there is already an existing
    // sycnedFavoriteFileIDs list then using that as the inital value.
    const [favoriteFileIDs, setFavoriteFileIDs] = useState<Set<number>>(
        syncedFavoriteFileIDs ?? new Set(),
    );
    //Set to store the IDs of the files which are in-flight for updation(favorite/unfavorite)
    const [pendingFavoriteUpdates, setPendingFavoriteUpdates] = useState<
        Set<number>
    >(new Set());
    //Set to store the IDs of the files which are in-flight for updation(archive/unarchive)
    const [pendingVisibilityUpdates, setPendingVisibilityUpdates] = useState<
        Set<number>
    >(new Set());

    useEffect(() => {
        if (!open || !user) return;

        // If there already exist an syncedFavoriteFileIDs then using that as inital value.
        if (syncedFavoriteFileIDs) {
            setFavoriteFileIDs(syncedFavoriteFileIDs);
            return;
        }

        /**
         * Each collectionFile has a collectionID associated with them, checking whether
         * that id matches with the id of each collectionFiles and if so then adding it to the
         * favoriteFileIDs.
         */
        const loadFavorites = async () => {
            const collections = await savedCollections();
            const collectionFiles = await savedCollectionFiles();

            for (const collection of collections) {
                if (
                    collection.type === "favorites" &&
                    collection.owner.id === user.id
                ) {
                    setFavoriteFileIDs(
                        deriveFavoriteFileIDs(
                            user.id,
                            collection.id,
                            collectionFiles,
                        ),
                    );
                    break;
                }
            }
        };

        void loadFavorites();
    }, [open, syncedFavoriteFileIDs, user]);

    // Helper to add/remove from Set immutably - avoids recreating Set when unnecessary
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

    // This function is triggered when if one visible shared/owned copy is toggled,
    // the equivalent copies update their star/pending UI together.
    const favoriteEquivalentFileIDs = useCallback(
        (file: EnteFile) => {
            // Getting the FileHashAndTypeKey of the file on which
            // the favorite toggle was triggered.
            const key = favoriteFileHashAndTypeKey(file);

            // If there is no key we can't compute the equivalent files
            // so returned just the original file.
            if (!key) return [file.id];

            const isSharedSourceFile = file.ownerID != user?.id;
            let firstOwnedEquivalentID: number | undefined;
            let hasFavoritedOwnedEquivalent = false;

            const fileIDs = new Set([file.id]);

            /**
             * Looping through the favoriteEquivalenceFiles and for the files
             * whose key match with the file's key.
             *
             * - If it's a shared file then adding to fileIDs
             *
             * - If it's a owned fie then already favorited, then updating the flag and
             *   and then adding it to the fileIDs.
             * - Else remembers the first owned equivalent ID
             */
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

            // Check favorite status at call time to avoid stale closure
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

/**
 * Manages the lifecycle of the currently visible journey photos.
 *
 * Tracks the ordered list of visible photos and exposes a setter to update them.
 * It's the visiblePhotos that are being shown in the Sidebar to the left of the map
 *
 * @returns An object containing the visible photos array and setter.
 */
function useVisiblePhotos() {
    const [visiblePhotos, setVisiblePhotos] = useState<MapPhotoPoint[]>([]);
    const [isVisiblePhotosUpdating, setIsVisiblePhotosUpdating] =
        useState(false);

    return {
        visiblePhotos,
        setVisiblePhotos,
        isVisiblePhotosUpdating,
        setIsVisiblePhotosUpdating,
    };
}

/**
 * Creates a marker icon for individual photos (no badge)
 * Used only in CollectionMapDialog for consistent styling
 */
function createMarkerIcon(
    imageSrc: string,
    size: number,
): import("leaflet").DivIcon | null {
    if (typeof window === "undefined") return null;

    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const leaflet = require("leaflet") as typeof import("leaflet");

    const pinSize = size + 16;
    const triangleHeight = 10;
    const pinHeight = pinSize + triangleHeight + 2;
    const hasImage = imageSrc && imageSrc.trim() !== "";

    const outerBorderRadius = 16;
    const innerBorderRadius = 12;

    return leaflet.divIcon({
        html: `
            <div class="photo-pin" style="
                width: ${pinSize}px;
                height: ${pinHeight}px;
                position: relative;
                cursor: pointer;
                transition: all 0.3s ease;
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
              onmouseover="this.style.background='#22c55e'; this.style.borderColor='#22c55e'; this.nextElementSibling.style.borderTopColor='#22c55e';"
              onmouseout="this.style.background='white'; this.style.borderColor='#ffffff'; this.nextElementSibling.style.borderTopColor='white';"
              >
                ${
                    hasImage
                        ? `<img src="${imageSrc}" style="width:100%;height:100%;object-fit:cover;border-radius:${innerBorderRadius}px;" alt="Location" />`
                        : `<div style="width:100%;height:100%;border-radius:${innerBorderRadius}px;animation:skeleton-pulse 1.5s ease-in-out infinite;"></div>
                           <style>@keyframes skeleton-pulse{0%{background-color:#ffffff}50%{background-color:#f0f0f0}100%{background-color:#ffffff}}</style>`
                }
              </div>
              <div style="
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
        className: "collection-marker",
        iconSize: [pinSize, pinHeight],
        iconAnchor: [pinSize / 2, pinHeight],
        popupAnchor: [0, -pinHeight],
    });
}

/**
 * Creates a cluster icon with badge popping out of the container
 * Used only in CollectionMapDialog for cluster markers
 */
function createClusterIcon(
    imageSrc: string,
    size: number,
    clusterCount: number,
    interactive = true,
): import("leaflet").DivIcon | null {
    if (typeof window === "undefined") return null;

    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const leaflet = require("leaflet") as typeof import("leaflet");

    const pinSize = size + 16;
    const triangleHeight = 10;
    const pinHeight = pinSize + triangleHeight + 2;
    const hasImage = imageSrc && imageSrc.trim() !== "";
    const badgeOverflow = 6;

    const outerBorderRadius = 16;
    const innerBorderRadius = 12;

    const hoverHandlers = interactive
        ? "onmouseover=\"this.style.background='#22c55e'; this.style.borderColor='#22c55e'; this.parentElement.querySelector('.triangle').style.borderTopColor='#22c55e';\" onmouseout=\"this.style.background='white'; this.style.borderColor='#ffffff'; this.parentElement.querySelector('.triangle').style.borderTopColor='white';\""
        : "";

    const badgeLabel =
        clusterCount >= 2000
            ? `${Math.floor((clusterCount - 1) / 1000)}K+`
            : clusterCount >= 1000
              ? "1K+"
              : clusterCount > 999
                ? `${Math.floor(clusterCount / 100)}00+`
                : `${clusterCount}`;

    return leaflet.divIcon({
        html: `
            <div class="photo-pin" style="
                width: ${pinSize}px;
                height: ${pinHeight}px;
                position: relative;
                cursor: ${interactive ? "pointer" : "default"};
                transition: all 0.3s ease;
                overflow: visible;
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
              <div style="
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
              ">
                  ${badgeLabel}
              </div>
              <style>
                .leaflet-marker-icon.collection-cluster-marker { overflow: visible !important; }
              </style>
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
        className: "collection-cluster-marker",
        iconSize: [pinSize + badgeOverflow, pinHeight + badgeOverflow],
        iconAnchor: [pinSize / 2, pinHeight],
        popupAnchor: [0, -pinHeight],
    });
}

// ============================================================================
// Helper Functions
// ============================================================================

// ============================================================================
// Main Component
// ============================================================================

/**
 * Main dialog component that displays a collection's photos on an interactive map
 * Responsibility: Coordinate all hooks, manage dialog state, render map layout or loading states
 */
export const CollectionMapDialog: React.FC<CollectionMapDialogProps> = ({
    open,
    onClose,
    collectionSummary,
    activeCollection,
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
    const optimalZoom = DEFAULT_MAP_ZOOM;
    const mapSourceCollectionFiles = mapFileSource?.collectionFiles ?? files;

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
        mapFileSource?.favoriteFileIDs,
    );
    const mapSourceHiddenFileIDs = mapFileSource?.hiddenFileIDs ?? emptyFileIDs;
    const mapSourceArchivedFileIDs =
        mapFileSource?.archivedFileIDs ?? emptyFileIDs;
    const mapSourceTempDeletedFileIDs =
        mapFileSource?.tempDeletedFileIDs ?? emptyFileIDs;
    const mapSourceTempHiddenFileIDs =
        mapFileSource?.tempHiddenFileIDs ?? emptyFileIDs;

    const mapFiles = useMemo(
        () =>
            deriveLocationAwareMapFiles({
                files,
                collectionFiles: mapSourceCollectionFiles,
                collectionSummaryType: collectionSummary.type,
                currentUserID: user?.id,
                favoriteFileIDs,
                hiddenFileIDs: mapSourceHiddenFileIDs,
                archivedFileIDs: mapSourceArchivedFileIDs,
                tempDeletedFileIDs: mapSourceTempDeletedFileIDs,
                tempHiddenFileIDs: mapSourceTempHiddenFileIDs,
            }),
        [
            collectionSummary.type,
            favoriteFileIDs,
            files,
            mapSourceArchivedFileIDs,
            mapSourceCollectionFiles,
            mapSourceHiddenFileIDs,
            mapSourceTempDeletedFileIDs,
            mapSourceTempHiddenFileIDs,
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

    const {
        visiblePhotos,
        setVisiblePhotos,
        isVisiblePhotosUpdating,
        setIsVisiblePhotosUpdating,
    } = useVisiblePhotos();

    useEffect(() => {
        if (!open) {
            setIsVisiblePhotosUpdating(false);
        }
    }, [open, setIsVisiblePhotosUpdating]);

    const handleSetFileViewerOpen: Dispatch<SetStateAction<boolean>> =
        useCallback(
            (next) => {
                const nextValue =
                    typeof next === "function" ? next(isFileViewerOpen) : next;
                setIsFileViewerOpen(nextValue);
            },
            [isFileViewerOpen],
        );

    // Convert visible map photo points to EnteFiles for FileListWithViewer
    const visibleFiles = useMemo(() => {
        return visiblePhotos
            .map((p) => filesByID.get(p.fileId))
            .filter((f): f is EnteFile => f !== undefined);
    }, [visiblePhotos, filesByID]);

    const handleRemotePull = useCallback(
        () =>
            onRemotePull
                ? onRemotePull({ silent: true, source: "map-dialog" })
                : Promise.resolve(),
        [onRemotePull],
    );
    const visualFeedback = useMemo(() => onVisualFeedback, [onVisualFeedback]);

    // Empty selection state since we don't support selection in map view
    const emptySelected = useMemo<SelectedState>(
        () => ({
            ownCount: 0,
            count: 0,
            context: undefined,
            collectionID: activeCollection?.id ?? collectionSummary.id,
        }),
        [activeCollection?.id, collectionSummary.id],
    );

    /**
     * Since the map view actually doesn't support the selecting from the sidebar
     * adding a empty function, other wise the setSelection must be made optional
     * which is a more system wide change and unncessary.
     */
    const noOpSetSelected = useCallback(() => {
        /* no-op */
    }, []);

    const handleMarkTempDeleted = useCallback(
        (files: EnteFile[]) => {
            //Triggering the gallery reducer's markTempDeleted
            onMarkTempDeleted?.(files);

            //remove the deleted files from the visible photos which are shown in the sidebar
            const idsToRemove = new Set(files.map((file) => file.id));
            setVisiblePhotos((prev) =>
                prev.filter((photo) => !idsToRemove.has(photo.fileId)),
            );
            removeFilesFromMap([...idsToRemove]);
        },
        [onMarkTempDeleted, removeFilesFromMap, setVisiblePhotos],
    );

    const handleFileVisibilityUpdateWithLocalState = useCallback(
        async (file: EnteFile, visibility: ItemVisibility) => {
            await handleFileVisibilityUpdate(file, visibility);
            const updatedMagicMetadata = file.magicMetadata
                ? {
                      ...file.magicMetadata,
                      data: { ...file.magicMetadata.data, visibility },
                  }
                : undefined;
            const updatedFile =
                updatedMagicMetadata !== undefined
                    ? { ...file, magicMetadata: updatedMagicMetadata }
                    : file;
            updateFileVisibility(updatedFile, visibility);
        },
        [handleFileVisibilityUpdate, updateFileVisibility],
    );

    const body = useMemo(() => {
        if (isLoading) {
            return (
                <CenteredBox>
                    <ActivityIndicator size="28px" />
                </CenteredBox>
            );
        }

        if (error) {
            return (
                <CenteredBox>
                    <Typography variant="body" sx={{ color: "text.secondary" }}>
                        {error}
                    </Typography>
                </CenteredBox>
            );
        }

        // Wait for map components to load (they're dynamically imported)
        if (!mapComponents) {
            return (
                <CenteredBox>
                    <ActivityIndicator size="28px" />
                </CenteredBox>
            );
        }

        if (!mapPoints.length || !mapCenter || !mapIndex) {
            return (
                <CenteredBox onClose={onClose} closeLabel={t("close")}>
                    <Typography variant="body" sx={{ color: "text.secondary" }}>
                        {t("no_geotagged_photos")}
                    </Typography>
                </CenteredBox>
            );
        }

        return (
            <MapLayout
                collectionSummary={collectionSummary}
                visiblePhotos={visiblePhotos}
                visibleFiles={visibleFiles}
                mapIndex={mapIndex}
                latestFileId={latestFileId}
                thumbByFileID={thumbByFileID}
                mapComponents={mapComponents}
                mapCenter={mapCenter}
                optimalZoom={optimalZoom}
                onClose={onClose}
                onVisiblePhotosChange={setVisiblePhotos}
                onVisiblePhotosLoadingChange={setIsVisiblePhotosUpdating}
                visiblePhotosUpdating={isVisiblePhotosUpdating}
                onPrefetchThumbnails={queueThumbnailFetch}
                user={user}
                favoriteFileIDs={favoriteFileIDs}
                pendingFavoriteUpdates={pendingFavoriteUpdates}
                pendingVisibilityUpdates={pendingVisibilityUpdates}
                onToggleFavorite={handleToggleFavorite}
                onFileVisibilityUpdate={
                    handleFileVisibilityUpdateWithLocalState
                }
                onRemotePull={handleRemotePull}
                onVisualFeedback={visualFeedback}
                onAddSaveGroup={onAddSaveGroup}
                onMarkTempDeleted={handleMarkTempDeleted}
                onAddFileToCollection={onAddFileToCollection}
                onRemoteFilesPull={onRemoteFilesPull}
                fileNormalCollectionIDs={fileNormalCollectionIDs}
                collectionNameByID={collectionNameByID}
                onSelectCollection={onSelectCollection}
                onSelectPerson={onSelectPerson}
                emailByUserID={emailByUserID}
                selected={emptySelected}
                setSelected={noOpSetSelected}
                onSetOpenFileViewer={handleSetFileViewerOpen}
            />
        );
    }, [
        collectionSummary,
        emptySelected,
        error,
        favoriteFileIDs,
        handleFileVisibilityUpdateWithLocalState,
        handleRemotePull,
        handleToggleFavorite,
        visualFeedback,
        isLoading,
        mapCenter,
        mapComponents,
        mapIndex,
        mapPoints,
        latestFileId,
        noOpSetSelected,
        optimalZoom,
        onAddFileToCollection,
        onAddSaveGroup,
        onRemoteFilesPull,
        pendingFavoriteUpdates,
        pendingVisibilityUpdates,
        setIsVisiblePhotosUpdating,
        setVisiblePhotos,
        collectionNameByID,
        fileNormalCollectionIDs,
        handleMarkTempDeleted,
        onSelectCollection,
        onSelectPerson,
        thumbByFileID,
        queueThumbnailFetch,
        user,
        visibleFiles,
        visiblePhotos,
        isVisiblePhotosUpdating,
        onClose,
        handleSetFileViewerOpen,
        emailByUserID,
    ]);

    return (
        <Dialog
            fullScreen
            keepMounted
            open={open}
            onClose={onClose}
            sx={{
                // When the FileViewer is open, lower this dialog's z-index below
                // PhotoSwipe's z-index (1199) so that FileViewer appears on top.
                // This avoids the visual glitch caused by closing/reopening the
                // dialog during transitions.
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

// ============================================================================
// Layout Components
// ============================================================================

/**
 * Main layout container for map and sidebar
 * Responsibility: Position sidebar and map canvas side-by-side
 */
interface MapLayoutProps {
    collectionSummary: CollectionSummary;
    visiblePhotos: MapPhotoPoint[];
    visibleFiles: EnteFile[];
    visiblePhotosUpdating: boolean;
    mapIndex: MapIndex | null;
    latestFileId: number | undefined;
    thumbByFileID: Map<number, string>;
    mapComponents: MapComponents;
    mapCenter: [number, number];
    optimalZoom: number;
    onClose: () => void;
    onVisiblePhotosChange: (photosInView: MapPhotoPoint[]) => void;
    onVisiblePhotosLoadingChange: (loading: boolean) => void;
    onPrefetchThumbnails: (fileIDs: number[]) => void;
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
    selected: SelectedState;
    setSelected: () => void;
}

function MapLayout({
    collectionSummary,
    visiblePhotos,
    visibleFiles,
    visiblePhotosUpdating,
    mapIndex,
    latestFileId,
    thumbByFileID,
    mapComponents,
    mapCenter,
    optimalZoom,
    onClose,
    onVisiblePhotosChange,
    onVisiblePhotosLoadingChange,
    onPrefetchThumbnails,
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
    selected,
    setSelected,
}: MapLayoutProps) {
    return (
        <Box sx={{ position: "relative", height: "100%", width: "100%" }}>
            <CollectionSidebar
                collectionSummary={collectionSummary}
                visibleCount={visiblePhotos.length}
                visibleFiles={visibleFiles}
                isVisiblePhotosUpdating={visiblePhotosUpdating}
                latestFileId={latestFileId}
                thumbByFileID={thumbByFileID}
                onClose={onClose}
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
                selected={selected}
                setSelected={setSelected}
                onSetOpenFileViewer={onSetOpenFileViewer}
            />
            <Box sx={{ width: "100%", height: "100%" }}>
                <MapCanvas
                    mapComponents={mapComponents}
                    mapCenter={mapCenter}
                    mapIndex={mapIndex}
                    optimalZoom={optimalZoom}
                    thumbByFileID={thumbByFileID}
                    onVisiblePhotosChange={onVisiblePhotosChange}
                    onVisiblePhotosLoadingChange={onVisiblePhotosLoadingChange}
                    onPrefetchThumbnails={onPrefetchThumbnails}
                />
            </Box>
        </Box>
    );
}

// ============================================================================
// Sidebar Components
// ============================================================================

/**
 * Sidebar displaying collection details and photo thumbnails using FileListWithViewer
 * Responsibility: Show collection cover, header, and file list with integrated viewer
 */
interface CollectionSidebarProps {
    collectionSummary: CollectionSummary;
    visibleCount: number;
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
    selected: SelectedState;
    setSelected: () => void;
}

// Fixed height for the cover image container (px)
const COVER_IMAGE_HEIGHT = 320;
const MOBILE_SIDEBAR_HEIGHT = "50%";
// Mobile has less padding: 8px top + 12px bottom + 2px margin = 22px
// Desktop has more padding: 16px top + 16px bottom + 2px margin = 34px
// Use desktop value for consistency in the virtualized list
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
    selected,
    setSelected,
}: CollectionSidebarProps) {
    const [currentDate, setCurrentDate] = useState<string | undefined>(
        undefined,
    );
    const [scrollOffset, setScrollOffset] = useState(0);
    const shouldShowCover = collectionSummary.type !== "all";
    const theme = useTheme();
    const isDarkMode = theme.palette.mode === "dark";
    const isMobile = useMediaQuery(theme.breakpoints.down("md"));

    // Get cover image: prioritize collection's coverFile, fallback to first photo
    const coverFile = collectionSummary.coverFile;
    const coverImageUrl = useMemo(() => {
        const coverThumb = coverFile && thumbByFileID.get(coverFile.id);
        if (coverThumb) return coverThumb;

        const fallbackId = latestFileId;
        return fallbackId ? thumbByFileID.get(fallbackId) : undefined;
    }, [coverFile, latestFileId, thumbByFileID]);

    // Create header component for FileListWithViewer (cover scrolls with content)
    const coverHeader = useMemo(() => {
        if (!shouldShowCover) return undefined;
        return {
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
        };
    }, [
        shouldShowCover,
        collectionSummary.name,
        collectionSummary.fileCount,
        coverImageUrl,
        onClose,
    ]);

    // Handle scroll events from the file list
    const handleScroll = useCallback((offset: number) => {
        setScrollOffset(offset);
    }, []);

    // Handle visible date changes from the file list
    const handleVisibleDateChange = useCallback((date: string | undefined) => {
        setCurrentDate(date);
    }, []);

    // Only show sticky date after scrolling past the cover header, or always for "All"
    const showStickyHeader =
        !shouldShowCover ||
        (scrollOffset > COVER_HEADER_HEIGHT && !!currentDate);
    const hasScrolled = scrollOffset > 0;
    const hideDateForAllNoScroll = !shouldShowCover && !hasScrolled;
    const hideDateForMobileNoScroll = isMobile && !hasScrolled;
    const visibleDate =
        currentDate && !hideDateForAllNoScroll && !hideDateForMobileNoScroll
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
                        <Box
                            sx={{
                                display: "flex",
                                alignItems: "center",
                                gap: 1,
                            }}
                        >
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
                            selected={selected}
                            setSelected={setSelected}
                            onSetOpenFileViewer={onSetOpenFileViewer}
                            listBorderRadius={isMobile ? "0" : "0 0 32px 32px"}
                            header={coverHeader}
                            onScroll={handleScroll}
                            onVisibleDateChange={handleVisibleDateChange}
                        />
                    ) : isVisiblePhotosUpdating ? null : (
                        <EmptyState>
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
                        </EmptyState>
                    )}
                </FileListContainer>
            </SidebarContainer>
            {isDarkMode && <SidebarGradient />}
        </SidebarWrapper>
    );
}

// ============================================================================
// Map Components
// ============================================================================

/**
 * Renders the Leaflet map with markers, clusters, and controls
 * Responsibility: Display interactive map with photo markers and handle viewport changes
 */
interface MapCanvasProps {
    mapComponents: MapComponents;
    mapCenter: [number, number];
    mapIndex: MapIndex | null;
    optimalZoom: number;
    thumbByFileID: Map<number, string>;
    onVisiblePhotosChange: (photosInView: MapPhotoPoint[]) => void;
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
    optimalZoom,
    thumbByFileID,
    onVisiblePhotosChange,
    onVisiblePhotosLoadingChange,
    onPrefetchThumbnails,
}: MapCanvasProps) {
    const { MapContainer, TileLayer, Marker, useMap } = mapComponents;

    return (
        <MapCanvasContainer>
            <MapContainer
                center={mapCenter}
                zoom={optimalZoom}
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
                {mapIndex && (
                    <MapClusters
                        useMap={useMap}
                        mapIndex={mapIndex}
                        thumbByFileID={thumbByFileID}
                        onVisiblePhotosChange={onVisiblePhotosChange}
                        onVisiblePhotosLoadingChange={
                            onVisiblePhotosLoadingChange
                        }
                        onPrefetchThumbnails={onPrefetchThumbnails}
                        Marker={Marker}
                    />
                )}
            </MapContainer>
        </MapCanvasContainer>
    );
});

/**
 * Floating map control buttons (open in Maps, zoom in/out)
 * Responsibility: Provide map navigation and external link controls
 */
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
            {/* Zoom controls: top left on mobile, bottom right on desktop */}
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
                {/* Location button: hidden on mobile, shown in stack on desktop */}
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

            {/* Location button: top right on mobile only */}
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

interface MapClustersProps {
    useMap: typeof import("react-leaflet").useMap;
    mapIndex: MapIndex;
    thumbByFileID: Map<number, string>;
    onVisiblePhotosChange: (photosInView: MapPhotoPoint[]) => void;
    onVisiblePhotosLoadingChange: (loading: boolean) => void;
    onPrefetchThumbnails: (fileIDs: number[]) => void;
    Marker: typeof import("react-leaflet").Marker;
}

const MapClusters = React.memo(function MapClusters({
    useMap,
    mapIndex,
    thumbByFileID,
    onVisiblePhotosChange,
    onVisiblePhotosLoadingChange,
    onPrefetchThumbnails,
    Marker,
}: MapClustersProps) {
    const map = useMap();
    const [features, setFeatures] = useState<MapFeature[]>([]);
    const previousVisibleIdsRef = useRef<Set<number>>(new Set());
    const visibleRequestIdRef = useRef(0);
    const iconCacheRef = useRef(
        new Map<string, ReturnType<typeof createMarkerIcon>>(),
    );

    const isClusterFeature = useCallback(
        (feature: MapFeature): feature is MapClusterFeature =>
            feature.properties.cluster === true,
        [],
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
                const nextVisiblePhotos = leaves.map((leaf) => {
                    const [lng, lat] = leaf.geometry.coordinates;
                    return {
                        lat,
                        lng,
                        name: "",
                        country: "",
                        image: "",
                        fileId: leaf.properties.fileId,
                    };
                });
                startTransition(() => {
                    onVisiblePhotosChange(nextVisiblePhotos);
                });
            }

            if (requestId === visibleRequestIdRef.current) {
                onVisiblePhotosLoadingChange(false);
            }
        },
        [
            isClusterFeature,
            mapIndex,
            onVisiblePhotosChange,
            onVisiblePhotosLoadingChange,
        ],
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
        setFeatures(clusters);

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

        if (prefetchTargets.size > 0) {
            onPrefetchThumbnails(Array.from(prefetchTargets));
        }
    }, [
        isClusterFeature,
        map,
        mapIndex,
        onPrefetchThumbnails,
        updateVisibleLeaves,
    ]);

    useEffect(() => {
        iconCacheRef.current.clear();
        previousVisibleIdsRef.current = new Set();
        visibleRequestIdRef.current += 1;
    }, [mapIndex]);

    const handleClusterClick = useCallback(
        (lat: number, lng: number, expansionZoom: number) => {
            map.setView([lat, lng], expansionZoom, { animate: true });
        },
        [map],
    );

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
                        icon = createClusterIcon(
                            thumb,
                            68,
                            count,
                            isInteractive,
                        );
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
                                              handleClusterClick(
                                                  lat,
                                                  lng,
                                                  expansionZoom,
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
                    icon = createMarkerIcon(thumb, 68);
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

// ============================================================================
// UI Components
// ============================================================================

/**
 * Styled floating action button with consistent styling
 * Responsibility: Provide consistent button styling for map controls
 */
const FloatingIconButton: React.FC<IconButtonProps> = ({ sx, ...props }) => {
    const baseSx = {
        bgcolor: (theme: {
            vars: { palette: { background: { paper: string } } };
        }) => theme.vars.palette.background.paper,
        boxShadow: (theme: { shadows: string[] }) => theme.shadows[4],
        width: 48,
        height: 48,
        borderRadius: "16px",
        transition: "transform 0.2s ease-out",
        "&:hover": {
            bgcolor: (theme: {
                vars: { palette: { background: { paper: string } } };
            }) => theme.vars.palette.background.paper,
            transform: "scale(1.05)",
        },
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

/**
 * Centered container for loading/error states with optional close button
 * Responsibility: Display centered content like loading spinners or error messages
 */
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

/**
 * Empty state placeholder for when no photos are visible
 * Responsibility: Display empty state message when no photos match filters
 */
function EmptyState({ children }: React.PropsWithChildren) {
    return <EmptyStateContainer>{children}</EmptyStateContainer>;
}

// ============================================================================
// Map Cover Component
// ============================================================================

/**
 * Hero image cover for the collection with title and memory count
 * Responsibility: Display collection cover image, name, and visible memory count
 */
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
    [theme.breakpoints.down("md")]: { borderRadius: "20px 20px 20px 20px" },
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

// ============================================================================
// Sidebar Styled Components
// ============================================================================

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
    borderRadius: "0",
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
    paddingTop: "0px",
    paddingBottom: "calc(env(safe-area-inset-bottom, 0px) + 16px)",
    [theme.breakpoints.up("md")]: {
        paddingTop: "0px",
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
    alignItems: "stretch",
    justifyContent: "flex-start",
    paddingTop: 0,
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
