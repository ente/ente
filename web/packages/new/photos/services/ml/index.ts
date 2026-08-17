import { proxy, transfer } from "comlink";
import { ensureLocalUser } from "ente-accounts/services/user";
import { isDesktop } from "ente-base/app";
import { blobCache } from "ente-base/blob-cache";
import { ensureElectron } from "ente-base/electron";
import log from "ente-base/log";
import { ensureMasterKeyFromSession } from "ente-base/session";
import { ComlinkWorker } from "ente-base/worker/comlink-worker";
import type { ProcessableUploadItem } from "ente-gallery/services/upload";
import { createUtilityProcess } from "ente-gallery/utils/native-worker";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { throttled } from "ente-utils/promise";
import pDebounce from "p-debounce";
import { getRemoteFlag, updateRemoteFlag } from "../remote-store";
import { setSearchPeople } from "../search";
import {
    addUserEntity,
    pullUserEntities,
    savedCGroups,
    updateOrCreateUserEntities,
    type CGroup,
} from "../user-entity";
import { deleteUserEntity } from "../user-entity/remote";
import type { ClusterFacesReason, FaceCluster } from "./cluster";
import { regenerateFaceCrops } from "./crop";
import {
    clearMLDB,
    resetFailedFileStatuses,
    savedFaceIndex,
    savedIndexCounts,
} from "./db";
import { fileIDFromFaceID } from "./face";
import {
    _applyPersonSuggestionUpdates,
    filterNamedPeople,
    reconstructPeopleState,
    type CGroupPerson,
    type PeopleState,
    type PersonSuggestionUpdates,
} from "./people";
import { MLWorker } from "./worker";
import type { CLIPMatches } from "./worker-types";

class MLState {
    isMLEnabled = false;
    comlinkWorker: Promise<ComlinkWorker<typeof MLWorker>> | undefined;
    isSyncing = false;
    mlStatusListeners: (() => void)[] = [];
    mlStatusSnapshot: MLStatus | undefined;
    peopleStateListeners: (() => void)[] = [];
    peopleStateSnapshot: PeopleState | undefined;
    needsResetFailures = false;
    inFlightFaceCropRegens = new Map<number, Promise<void>>();
    faceCropObjectURLCache = new Map<string, string>();
}

let _state = new MLState();
// Reinitializing would erase people until the next sync.
let _didInitML = false;

const worker = () =>
    (_state.comlinkWorker ??= createComlinkWorker()).then((cw) => cw.remote);

const createComlinkWorker = async () => {
    const electron = ensureElectron();
    const delegate = {
        workerDidUpdateStatus,
        workerDidUnawaitedIndex,
        workerDidLoseElectronPort,
    };

    const messagePort = await createUtilityProcess(electron, "ml");

    const cw = new ComlinkWorker<typeof MLWorker>(
        "ML",
        new Worker(new URL("worker.ts", import.meta.url)),
    );

    await cw.remote.then((w) =>
        w.init(transfer(messagePort, [messagePort]), proxy(delegate)),
    );

    return cw;
};

export const terminateMLWorker = async () => {
    if (_state.comlinkWorker) {
        await _state.comlinkWorker.then((cw) => cw.terminate());
        _state.comlinkWorker = undefined;
    }
};

export const isMLSupported = isDesktop;

export const initML = () => {
    if (_didInitML) return;
    _state.isMLEnabled = isMLEnabledLocal();
    resetPeopleStateSnapshot();
    _didInitML = true;
};

// Terminate the worker first; each context caches its own IDB connection.
export const logoutML = async () => {
    [..._state.faceCropObjectURLCache.values()].forEach((url) =>
        URL.revokeObjectURL(url),
    );
    _state = new MLState();
    _didInitML = false;
    await clearMLDB();
};

export const isMLEnabled = () => _state.isMLEnabled;
export const enableML = async () => {
    await updateIsMLEnabledRemote(true);
    setIsMLEnabledLocal(true);
    _state.isMLEnabled = true;
    setInterimScheduledStatus();
    resetPeopleStateSnapshot();
    void updateMLStatusSnapshot().then(() => mlSync("enable-ml"));
};

export const disableML = async () => {
    await updateIsMLEnabledRemote(false);
    setIsMLEnabledLocal(false);
    _state.isMLEnabled = false;
    _state.isSyncing = false;
    await terminateMLWorker();
    triggerStatusUpdate();
    resetPeopleStateSnapshot();
};

const mlLocalKey = "mlEnabled";

const isMLEnabledLocal = () => localStorage.getItem(mlLocalKey) == "1";

const setIsMLEnabledLocal = (enabled: boolean) =>
    enabled
        ? localStorage.setItem(mlLocalKey, "1")
        : localStorage.removeItem(mlLocalKey);

// This legacy key now controls all ML, not only face search.
const mlRemoteKey = "faceSearchEnabled";

const getIsMLEnabledRemote = () => getRemoteFlag(mlRemoteKey);

const updateIsMLEnabledRemote = (enabled: boolean) =>
    updateRemoteFlag(mlRemoteKey, enabled);

export const retryIndexingFailuresIfNeeded = () => {
    _state.needsResetFailures = true;
};

export const pullMLStatus = async () => {
    _state.isMLEnabled = await getIsMLEnabledRemote();
    setIsMLEnabledLocal(_state.isMLEnabled);
    return updateMLStatusSnapshot();
};

export const mlSync = async (reason: ClusterFacesReason = "ml-sync") => {
    if (!_state.isMLEnabled) return;
    if (_state.isSyncing) return;
    _state.isSyncing = true;

    try {
        if (_state.needsResetFailures) {
            _state.needsResetFailures = false;
            await resetFailedFileStatuses();
        }

        // Keep the order: files, faces, cgroups, clusters, then people.
        await worker().then((w) => w.index());

        await updateClustersAndPeople(reason);
    } finally {
        _state.isSyncing = false;
    }
};

const updateClustersAndPeople = async (reason: ClusterFacesReason) => {
    const masterKey = await ensureMasterKeyFromSession();

    await pullUserEntities("cgroup", masterKey);

    await (await worker()).clusterFaces(masterKey, reason);

    await updatePeopleState();
};

// Uploads arrive one by one; avoid reclustering after every file.
const debounceUpdateClustersAndPeople = pDebounce(
    updateClustersAndPeople,
    30 * 1e3,
);

const workerDidLoseElectronPort = () => {
    log.error("Discarding the ML worker since its utility process exited");
    void terminateMLWorker();
};

const workerDidUnawaitedIndex = () =>
    void debounceUpdateClustersAndPeople("live-upload-index");

export const indexNewUpload = (
    file: EnteFile,
    processableUploadItem: ProcessableUploadItem,
) => {
    if (!isMLEnabled()) return;
    if (!isDesktop) return;
    if (file.metadata.fileType != FileType.image) return;
    log.debug(() => ["ml/liveq", { file, processableUploadItem }]);
    void worker().then((w) => w.onUpload(file, processableUploadItem));
};

export type MLStatus =
    | { phase: "disabled" }
    | {
          phase: "scheduled" | "indexing" | "fetching" | "clustering" | "done";
          phaseFailed?: boolean;
          nSyncedFiles: number;
          nTotalFiles: number;
      };

export const mlStatusSubscribe = (onChange: () => void): (() => void) => {
    _state.mlStatusListeners.push(onChange);
    return () => {
        _state.mlStatusListeners = _state.mlStatusListeners.filter(
            (l) => l != onChange,
        );
    };
};

export const mlStatusSnapshot = (): MLStatus | undefined => {
    if (!isMLSupported) return undefined;

    const result = _state.mlStatusSnapshot;
    if (!result) triggerStatusUpdate();
    return result;
};

const triggerStatusUpdate = () => void updateMLStatusSnapshot();

const updateMLStatusSnapshot = async () =>
    setMLStatusSnapshot(await getMLStatus());

const setMLStatusSnapshot = (snapshot: MLStatus) => {
    _state.mlStatusSnapshot = snapshot;
    _state.mlStatusListeners.forEach((l) => l());
};

const getMLStatus = async (): Promise<MLStatus> => {
    if (!_state.isMLEnabled) return { phase: "disabled" };

    const w = await worker();

    const clusteringProgress = await w.clusteringProgress;
    if (clusteringProgress) {
        return {
            phase: "clustering",
            nSyncedFiles: clusteringProgress.completed,
            nTotalFiles: clusteringProgress.total,
        };
    }

    const { indexedCount, indexableCount, failedCount } =
        await savedIndexCounts();

    // Live uploads lack file-status rows, so worker state wins over counts.
    let phase: MLStatus["phase"];
    let phaseFailed = false;
    const state = await w.state;
    if (state == "indexing" || state == "fetching") {
        phase = state;
    } else if (state == "init" || indexableCount > 0) {
        phase = "scheduled";
    } else {
        phase = "done";
        phaseFailed = failedCount > indexedCount && failedCount > 500;
    }

    return {
        phase,
        phaseFailed,
        nSyncedFiles: indexedCount,
        nTotalFiles: indexableCount + indexedCount,
    };
};

const setInterimScheduledStatus = () => {
    let nSyncedFiles = 0,
        nTotalFiles = 0;
    if (
        _state.mlStatusSnapshot &&
        _state.mlStatusSnapshot.phase != "disabled"
    ) {
        ({ nSyncedFiles, nTotalFiles } = _state.mlStatusSnapshot);
    }
    setMLStatusSnapshot({ phase: "scheduled", nSyncedFiles, nTotalFiles });
};

const workerDidUpdateStatus = throttled(updateMLStatusSnapshot, 2000);

export const peopleStateSubscribe = (onChange: () => void): (() => void) => {
    _state.peopleStateListeners.push(onChange);
    return () => {
        _state.peopleStateListeners = _state.peopleStateListeners.filter(
            (l) => l != onChange,
        );
    };
};

// Undefined means disabled; an empty state means enabled but loading or empty.
const resetPeopleStateSnapshot = () =>
    setPeopleStateSnapshot(
        _state.isMLEnabled
            ? { people: [], visiblePeople: [], personByFaceID: new Map() }
            : undefined,
    );

export const peopleStateSnapshot = () => _state.peopleStateSnapshot;

const updatePeopleState = async () => {
    const state = await reconstructPeopleState();

    setSearchPeople(filterNamedPeople(state.visiblePeople));

    setPeopleStateSnapshot(state);
};

const setPeopleStateSnapshot = (snapshot: PeopleState | undefined) => {
    _state.peopleStateSnapshot = snapshot;
    _state.peopleStateListeners.forEach((l) => l());
};

export const clipMatches = (
    searchPhrase: string,
): Promise<CLIPMatches | undefined> =>
    worker().then((w) => w.clipMatches(searchPhrase));

export interface AnnotatedFaceID {
    faceID: string;
    personID: string;
    personName: string | undefined;
}

export const getAnnotatedFacesForFile = async (
    file: EnteFile,
): Promise<AnnotatedFaceID[]> => {
    if (!isMLEnabled()) return [];

    const index = await savedFaceIndex(file.id);
    if (!index) return [];

    const personByFaceID = _state.peopleStateSnapshot?.personByFaceID;
    if (!personByFaceID) return [];

    const sortableFaces: [AnnotatedFaceID, number][] = [];
    for (const { faceID } of index.faces) {
        const person = personByFaceID.get(faceID);
        if (!person) continue;
        sortableFaces.push([
            { faceID, personID: person.id, personName: person.name },
            person.fileIDs.length,
        ]);
    }

    sortableFaces.sort((a, b) => {
        if (a[0].personName && !b[0].personName) return -1;
        if (!a[0].personName && b[0].personName) return 1;
        return b[1] - a[1];
    });
    return sortableFaces.map(([f]) => f);
};

export const faceCrop = async (faceID: string, file: EnteFile) => {
    // Returned object URLs are cache-owned; callers must not revoke them.
    let inFlight = _state.inFlightFaceCropRegens.get(file.id);

    if (!inFlight) {
        inFlight = regenerateFaceCropsIfNeeded(file);
        _state.inFlightFaceCropRegens.set(file.id, inFlight);
    }

    await inFlight;

    let url = _state.faceCropObjectURLCache.get(faceID);
    if (!url) {
        const cache = await blobCache("face-crops");
        const blob = await cache.get(faceID);
        if (blob) {
            url = URL.createObjectURL(blob);
            if (url) _state.faceCropObjectURLCache.set(faceID, url);
        }
    }

    return url;
};

const regenerateFaceCropsIfNeeded = async (file: EnteFile) => {
    const index = await savedFaceIndex(file.id);
    if (!index) return;

    const cache = await blobCache("face-crops");
    const faceIDs = index.faces.map((f) => f.faceID);
    let needsRegen = false;
    for (const id of faceIDs) if (!(await cache.has(id))) needsRegen = true;

    if (needsRegen) await regenerateFaceCrops(file, index);
};

export const addCGroup = async (name: string, cluster: FaceCluster) => {
    const id = await addUserEntity(
        "cgroup",
        {
            name,
            assigned: [cluster],
            isHidden: false,
            isPinned: false,
            hideFromMemories: false,
        },
        await ensureMasterKeyFromSession(),
    );
    await mlSync("add-cgroup");
    return id;
};

export const addClusterToCGroup = async (
    cgroup: CGroup,
    cluster: FaceCluster,
) => {
    const clusterFaceIDs = new Set(cluster.faces);
    const assigned = cgroup.data.assigned.concat([cluster]);
    const rejectedFaceIDs = cgroup.data.rejectedFaceIDs.filter(
        (id) => !clusterFaceIDs.has(id),
    );

    await updateOrCreateUserEntities(
        "cgroup",
        [{ ...cgroup, data: { ...cgroup.data, assigned, rejectedFaceIDs } }],
        await ensureMasterKeyFromSession(),
    );
    return mlSync("add-cluster-to-cgroup");
};

export const renameCGroup = async (cgroup: CGroup, name: string) => {
    await updateOrCreateUserEntities(
        "cgroup",
        [{ ...cgroup, data: { ...cgroup.data, name } }],
        await ensureMasterKeyFromSession(),
    );
    return mlSync("rename-cgroup");
};

export const deleteCGroup = async ({ id }: CGroup) => {
    await deleteUserEntity(id);
    return mlSync("delete-cgroup");
};

export const setCGroupPinned = async (cgroup: CGroup, isPinned: boolean) => {
    await updateOrCreateUserEntities(
        "cgroup",
        [{ ...cgroup, data: { ...cgroup.data, isPinned } }],
        await ensureMasterKeyFromSession(),
    );
    return mlSync("set-cgroup-pinned");
};

export const pinCGroup = async (cgroup: CGroup) =>
    setCGroupPinned(cgroup, true);

export const unpinCGroup = async (cgroup: CGroup) =>
    setCGroupPinned(cgroup, false);

export interface ManualPersonAssignmentResult {
    addedFileIDs: number[];
    alreadyAssignedFileIDs: number[];
}

export const addManualFileAssignmentsToPerson = async (
    personID: string,
    fileIDs: Iterable<number>,
): Promise<ManualPersonAssignmentResult> => {
    if (!isMLEnabled()) return { addedFileIDs: [], alreadyAssignedFileIDs: [] };

    const uniqueFileIDs = [...new Set(fileIDs)].filter(
        (id) => typeof id == "number" && !isNaN(id),
    );
    if (!uniqueFileIDs.length)
        return { addedFileIDs: [], alreadyAssignedFileIDs: [] };

    const cgroup = (await savedCGroups()).find((c) => c.id == personID);
    if (!cgroup)
        throw new Error(
            `addManualFileAssignmentsToPerson: missing cgroup ${personID}`,
        );

    const existingClusterFileIDs = new Set<number>();
    for (const cluster of cgroup.data.assigned) {
        for (const faceID of cluster.faces) {
            const fileID = fileIDFromFaceID(faceID);
            if (fileID) existingClusterFileIDs.add(fileID);
        }
    }

    const manualFileIDs = new Set(cgroup.data.manuallyAssigned);

    const addedFileIDs: number[] = [];
    const alreadyAssignedFileIDs: number[] = [];
    for (const id of uniqueFileIDs) {
        if (existingClusterFileIDs.has(id) || manualFileIDs.has(id)) {
            alreadyAssignedFileIDs.push(id);
        } else {
            addedFileIDs.push(id);
        }
    }

    if (!addedFileIDs.length) return { addedFileIDs, alreadyAssignedFileIDs };

    const masterKey = await ensureMasterKeyFromSession();
    await updateOrCreateUserEntities(
        "cgroup",
        [
            {
                ...cgroup,
                data: {
                    ...cgroup.data,
                    manuallyAssigned: [...manualFileIDs, ...addedFileIDs],
                },
            },
        ],
        masterKey,
    );

    await pullUserEntities("cgroup", masterKey);
    await updatePeopleState();

    return { addedFileIDs, alreadyAssignedFileIDs };
};

export const suggestionsAndChoicesForPerson = async (person: CGroupPerson) =>
    worker().then((w) =>
        // Workers cannot read the browser session.
        w.suggestionsAndChoicesForPerson(person, ensureLocalUser().id),
    );

export const applyPersonSuggestionUpdates = async (
    cgroup: CGroup,
    updates: PersonSuggestionUpdates,
) => {
    await _applyPersonSuggestionUpdates(
        cgroup,
        updates,
        await ensureMasterKeyFromSession(),
    );
    return mlSync("apply-person-suggestion-updates");
};

export const ignoreCluster = async (cluster: FaceCluster) => {
    await addUserEntity(
        "cgroup",
        {
            name: "",
            assigned: [cluster],
            isHidden: true,
            isPinned: false,
            hideFromMemories: false,
        },
        await ensureMasterKeyFromSession(),
    );
    return mlSync("ignore-cluster");
};
