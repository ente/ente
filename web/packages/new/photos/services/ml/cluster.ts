import { assertionFailed } from "ente-base/assert";
import { newNonSecureID } from "ente-base/id-worker";
import log from "ente-base/log";
import type { EnteFile } from "ente-media/file";
import { fileCreationPhotoSortTime } from "ente-media/file-metadata";
import { wait } from "ente-utils/promise";
import {
    pullUserEntities,
    savedCGroups,
    updateOrCreateUserEntities,
} from "../user-entity";
import { savedFaceClusters, saveFaceClusters } from "./db";
import {
    faceDirection,
    fileIDFromFaceID,
    type Face,
    type FaceIndex,
} from "./face";
import { dotProduct } from "./math";

/**
 * A face cluster is an set of faces, and a nanoid to uniquely identify it.
 *
 * These are local only clusters. The clusters that are synced with remote are
 * part of "cgroup" user entities.
 */
export interface FaceCluster {
    /**
     * A nanoid for this cluster.
     */
    id: string;
    /**
     * An unordered set of ids of the faces that belong to this cluster.
     *
     * For ease of transportation and persistence this is an array, but it
     * should conceptually be thought of as a set.
     */
    faces: string[];
}

export interface ClusteringProgress {
    completed: number;
    total: number;
}

export type ClusterFacesReason =
    | "add-cgroup"
    | "add-cluster-to-cgroup"
    | "apply-person-suggestion-updates"
    | "delete-cgroup"
    | "enable-ml"
    | "ignore-cluster"
    | "live-upload-index"
    | "ml-sync"
    | "remote-pull"
    | `remote-pull:${string}`
    | "rename-cgroup"
    | "set-cgroup-pinned";

/** A {@link Face} annotated with data needed during clustering. */
export type ClusterFace = Omit<Face, "embedding"> & {
    embedding: Float32Array;
    isBadFace: boolean;
};

/**
 * Generates clusters from the given faces using a batched form of linear
 * clustering, with a bit of lookback (and a dollop of heuristics) to get the
 * clusters to merge across batches.
 *
 * The same logic is used for both the initial clustering and subsequent
 * incremental updates, just that the incremental updates will be much faster
 * since most of the files will be skipped (as they already have a cluster
 * assigned to them).
 *
 * [Note: Draining the event loop during clustering]
 *
 * The clustering is a synchronous operation, but we make it async to
 * artificially drain the worker's event loop after each mini-batch so that
 * other interactions with the worker (where this code runs) do not get stalled
 * while clustering is in progress.
 */
export const _clusterFaces = async (
    faceIndexes: FaceIndex[],
    localFiles: EnteFile[],
    onProgress: (progress: ClusteringProgress) => void,
    reason: ClusterFacesReason,
) => {
    const startTime = Date.now();

    // A flattened array of filtered and annotated faces.
    const filteredFaces = [...enumerateFaces(faceIndexes)];

    // Sort faces temporally (a heuristic for better clusters), with the newest
    // ones first.
    const faces = sortFacesNewestOnesFirst(filteredFaces, localFiles);

    // Start with clusters we have currently (whether from remote or from a
    // previous local run, but preferring the remote ones).
    let clusters: FaceCluster[] = [];

    // Get the locally available remote cluster groups.
    const cgroups = await savedCGroups();

    // Sort them so that the latest ones are first.
    //
    // This is not expected to be something that makes a functional difference
    // but is done as part of a general theme of not making strict assumptions
    // about the clusters we get from remote.
    //
    // In particular, the same face ID can be in different clusters. In such
    // cases we should assign it arbitrarily assign it to the last cluster we
    // find it in. Such leeway is intentionally provided to allow clients some
    // slack in how they implement the sync without needing to make an blocking
    // API request for every user interaction.

    const sortedCGroups = cgroups.sort((a, b) => b.updatedAt - a.updatedAt);

    // Fill in clusters from remote cgroups, and also construct rejected lookup.
    const rejectedClusterIDsForFaceID = new Map<string, Set<string>>();
    for (const cgroup of sortedCGroups) {
        if (cgroup.data.rejectedFaceIDs.length == 0) {
            clusters = clusters.concat(cgroup.data.assigned);
        } else {
            const rejectedFaceIDs = new Set(cgroup.data.rejectedFaceIDs);
            clusters = clusters.concat(
                cgroup.data.assigned.map((cluster) => ({
                    ...cluster,
                    faces: cluster.faces.filter((f) => !rejectedFaceIDs.has(f)),
                })),
            );
            for (const faceID of rejectedFaceIDs) {
                const s = rejectedClusterIDsForFaceID.get(faceID) ?? new Set();
                cgroup.data.assigned.forEach(({ id }) => s.add(id));
                rejectedClusterIDsForFaceID.set(faceID, s);
            }
        }
    }

    // Add on the clusters we have available locally.
    clusters = clusters.concat(await savedFaceClusters());

    // For fast reverse lookup - map from the id of a face to the id of the
    // cluster to which it belongs.
    const faceIDToClusterID = new Map<string, string>();

    // For fast reverse lookup - map from the id of a face to the index of its
    // corresponding cluster in the clusters array.
    const faceIDToClusterIndex = new Map<string, number>();

    // Fill in the maps with the existing data. Since the remote clusters come
    // first, they'll be preferred over any existing local clusters for the same
    // face (as is the desired behaviour).

    for (const [i, cluster] of clusters.entries()) {
        for (const faceID of cluster.faces) {
            if (!faceIDToClusterID.has(faceID)) {
                faceIDToClusterID.set(faceID, cluster.id);
                faceIDToClusterIndex.set(faceID, i);
            }
        }
    }

    // IDs of the clusters which were modified. We use this information to
    // determine which cgroups need to be updated on remote.
    const modifiedClusterIDs = new Set<string>();

    const state = {
        faceIDToClusterID,
        faceIDToClusterIndex,
        clusters,
        modifiedClusterIDs,
    };

    // Process the faces in batches, but keep an overlap between batches to
    // allow "links" to form with existing clusters.

    const total = faces.length;
    const batchSize = 10000;
    const offsetIncrement = 7500;

    for (let offset = 0; offset < total; offset += offsetIncrement) {
        await clusterBatchLinear(
            faces.slice(offset, offset + batchSize),
            state,
            rejectedClusterIDsForFaceID,
            ({ completed }) =>
                onProgress({ completed: offset + completed, total }),
        );
    }

    const t = `(${Date.now() - startTime} ms)`;
    log.info(
        `Refreshed ${clusters.length} clusters from ${total} faces ${t} [reason=${reason}]`,
    );

    return { clusters, modifiedClusterIDs };
};

/**
 * A generator function that returns a stream of eligible {@link ClusterFace}s
 * by flattening all the the faces present in the given {@link faceIndices}.
 *
 * During this, it also converts the embeddings to Float32Arrays to speed up the
 * dot product calculations that will happen during clustering and attaches
 * other information that the clustering algorithm needs.
 */
function* enumerateFaces(faceIndices: FaceIndex[]) {
    for (const fi of faceIndices) {
        for (const face of fi.faces) {
            if (face.blur > 10 && face.score > 0.8) {
                yield {
                    ...face,
                    embedding: new Float32Array(face.embedding),
                    isBadFace: isBadFace(face),
                };
            }
        }
    }
}

/**
 * Sort faces by the local photo creation date of the file which contains them.
 * The sorting is in descending order, so the newest file is first.
 *
 * Sorting faces temporally is meant as a heuristic for better clusters.
 */
const sortFacesNewestOnesFirst = (
    faces: ClusterFace[],
    localFiles: EnteFile[],
) => {
    const localFileByID = new Map(localFiles.map((f) => [f.id, f]));
    // In unexpected scenarios, we might run clustering without having the
    // corresponding EnteFile available locally. This shouldn't happen, so log
    // an warning, but meanwhile let the clustering proceed by assigning such
    // files an arbitrary sort time.
    const sortTimeByFaceID = new Map<string, number>();
    for (const { faceID } of faces) {
        const file = localFileByID.get(fileIDFromFaceID(faceID)!);
        if (!file) {
            assertionFailed(`Did not find a local file for faceID ${faceID}`);
            sortTimeByFaceID.set(faceID, 0);
        } else {
            sortTimeByFaceID.set(faceID, fileCreationPhotoSortTime(file));
        }
    }

    const sortTimeForFace = ({ faceID }: { faceID: string }) =>
        sortTimeByFaceID.get(faceID) ?? 0;

    return faces.sort((a, b) => sortTimeForFace(b) - sortTimeForFace(a));
};

/**
 * Return true if the given face is above the minimum inclusion thresholds, but
 * is otherwise heuristically determined to be possibly spurious face detection.
 *
 * We apply a higher threshold when clustering such faces.
 */
const isBadFace = (face: Face) =>
    face.blur < 50 ||
    (face.blur < 200 && face.blur < 0.85) ||
    isSidewaysFace(face);

const isSidewaysFace = (face: Face) =>
    faceDirection(face.detection) != "straight";

/** Generate a new cluster ID. */
const newClusterID = () => newNonSecureID("cluster_");

interface ClusteringState {
    faceIDToClusterID: Map<string, string>;
    faceIDToClusterIndex: Map<string, number>;
    clusters: FaceCluster[];
    modifiedClusterIDs: Set<string>;
}

const clusterBatchLinear = async (
    batch: ClusterFace[],
    state: ClusteringState,
    rejectedClusterIDsForFaceID: Map<string, Set<string>>,
    onProgress: (progress: ClusteringProgress) => void,
) => {
    const [clusteredFaces, unclusteredFaces] = batch.reduce<
        [ClusterFace[], ClusterFace[]]
    >(
        (split, face) => (
            split[state.faceIDToClusterID.has(face.faceID) ? 0 : 1].push(face),
            split
        ),
        [[], []],
    );

    if (!unclusteredFaces.length) {
        // Optimization: early exit if nothing in batch is unclustered. In a
        // single test (so it might be not be a universal benefit) of ~8k faces,
        // it helped reduce the no-op time by 10x.
        onProgress({ completed: batch.length, total: batch.length });
        return;
    }

    // Sort the faces so that the already clustered ones are at the front.
    const faces = clusteredFaces.concat(unclusteredFaces);

    // For each face in the batch
    for (const [i, fi] of faces.entries()) {
        if (i % 100 == 0) {
            onProgress({ completed: i, total: batch.length });
            // See: [Note: Draining the event loop during clustering]
            await wait(0);
        }

        // If the face is already part of a cluster, then skip it.
        if (state.faceIDToClusterID.has(fi.faceID)) continue;

        const rejectedClusters = rejectedClusterIDsForFaceID.get(fi.faceID);

        // Find the nearest neighbour among the previous faces in this batch.
        let nnIndex: number | undefined;
        let nnCosineSimilarity = 0;
        for (let j = i - 1; j >= 0; j--) {
            // ! This is an O(n^2) loop, be careful when adding more code here.

            const fj = faces[j]!;

            // The vectors are already normalized, so we can directly use their
            // dot product as their cosine similarity.
            const csim = dotProduct(fi.embedding, fj.embedding);
            if (csim <= nnCosineSimilarity) continue;

            const threshold = fj.isBadFace ? 0.84 : 0.76;
            if (csim < threshold) continue;

            // Don't add the face back to a cluster it has been rejected from.
            if (rejectedClusters) {
                const cjx = state.faceIDToClusterIndex.get(fj.faceID);
                if (cjx !== undefined) {
                    const cj = state.clusters[cjx]!;
                    if (rejectedClusters.has(cj.id)) {
                        continue;
                    }
                }
            }

            nnIndex = j;
            nnCosineSimilarity = csim;
        }

        if (nnIndex !== undefined) {
            // Found a neighbour close enough, add ourselves to its cluster.
            const nnFace = faces[nnIndex]!;
            const nnClusterIndex = state.faceIDToClusterIndex.get(
                nnFace.faceID,
            )!;
            const nnCluster = state.clusters[nnClusterIndex]!;

            state.faceIDToClusterID.set(fi.faceID, nnCluster.id);
            state.faceIDToClusterIndex.set(fi.faceID, nnClusterIndex);
            nnCluster.faces.push(fi.faceID);
            state.modifiedClusterIDs.add(nnCluster.id);
        } else {
            // No neighbour within the threshold. Create a new cluster.
            const clusterID = newClusterID();
            const clusterIndex = state.clusters.length;
            const cluster = { id: clusterID, faces: [fi.faceID] };

            state.faceIDToClusterID.set(fi.faceID, cluster.id);
            state.faceIDToClusterIndex.set(fi.faceID, clusterIndex);
            state.clusters.push(cluster);
            state.modifiedClusterIDs.add(cluster.id);
        }
    }
};

/**
 * Use the output of the clustering phase to (a) update any remote cgroups that
 * have changed, and (b) update our locally persisted clusters.
 *
 * @param masterKey The user's master key (as a base64 string), required for
 * updating the cgroups on remote if needed.
 */
export const reconcileClusters = async (
    clusters: FaceCluster[],
    modifiedClusterIDs: Set<string>,
    masterKey: string,
) => {
    // Index clusters by their ID for fast lookup.
    const clusterByID = new Map(clusters.map((c) => [c.id, c]));

    // Get the existing remote cluster groups.
    const cgroups = await savedCGroups();

    // Find the cgroups that have changed since we started.
    const changedCGroups = cgroups
        .map((cgroup) => {
            for (const cluster of cgroup.data.assigned) {
                if (modifiedClusterIDs.has(cluster.id)) {
                    return {
                        ...cgroup,
                        data: {
                            ...cgroup.data,
                            // Map assigned cluster IDs to latest cluster objects.
                            // If any referenced cluster is missing, throw to avoid
                            // silently losing data or writing nulls to remote.
                            assigned: cgroup.data.assigned.map(({ id }) => {
                                const c = clusterByID.get(id);
                                if (!c)
                                    throw new Error(
                                        `reconcileClusters: missing cluster ${id} for cgroup ${cgroup.id}`,
                                    );
                                return c;
                            }),
                        },
                    };
                }
            }
            return undefined;
        })
        .filter((g) => !!g);

    // Update remote if needed.
    if (changedCGroups.length) {
        await updateOrCreateUserEntities("cgroup", changedCGroups, masterKey);
        log.info(`Updated ${changedCGroups.length} remote cgroups`);
    }

    // Find which clusters are part of remote cgroups.
    const isRemoteClusterID = new Set<string>();
    for (const cgroup of cgroups) {
        for (const cluster of cgroup.data.assigned)
            isRemoteClusterID.add(cluster.id);
    }

    // Locally save clusters that are not part of any remote cgroup.
    await saveFaceClusters(
        clusters.filter(({ id }) => !isRemoteClusterID.has(id)),
    );

    // Refresh our local state if we'd updated remote.
    if (changedCGroups.length) await pullUserEntities("cgroup", masterKey);
};
