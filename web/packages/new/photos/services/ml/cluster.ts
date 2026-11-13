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

// Local-only; synced clusters live in cgroup user entities.
export interface FaceCluster {
    id: string;
    // Treat this as a set even though persistence uses an array.
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

export type ClusterFace = Omit<Face, "embedding"> & {
    embedding: Float32Array;
    isBadFace: boolean;
};

export const _clusterFaces = async (
    faceIndexes: FaceIndex[],
    localFiles: EnteFile[],
    onProgress: (progress: ClusteringProgress) => void,
    reason: ClusterFacesReason,
) => {
    const startTime = Date.now();

    const filteredFaces = [...enumerateFaces(faceIndexes)];

    // Newest faces first improves the clustering heuristic.
    const faces = sortFacesNewestOnesFirst(filteredFaces, localFiles);

    let clusters: FaceCluster[] = [];

    const cgroups = await savedCGroups();

    // A face can occur in multiple remote clusters; newest assignment wins.
    const sortedCGroups = cgroups.sort((a, b) => b.updatedAt - a.updatedAt);

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

    clusters = clusters.concat(await savedFaceClusters());

    const faceIDToClusterID = new Map<string, string>();

    const faceIDToClusterIndex = new Map<string, number>();

    // Remote assignments precede and override duplicate local assignments.
    for (const [i, cluster] of clusters.entries()) {
        for (const faceID of cluster.faces) {
            if (!faceIDToClusterID.has(faceID)) {
                faceIDToClusterID.set(faceID, cluster.id);
                faceIDToClusterIndex.set(faceID, i);
            }
        }
    }

    const modifiedClusterIDs = new Set<string>();

    const state = {
        faceIDToClusterID,
        faceIDToClusterIndex,
        clusters,
        modifiedClusterIDs,
    };

    // Overlap batches so clusters can link across their boundaries.
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

function* enumerateFaces(faceIndices: FaceIndex[]) {
    for (const fi of faceIndices) {
        for (const face of fi.faces) {
            if (face.blur > 10 && face.score > 0.8) {
                yield {
                    ...face,
                    // Convert once; dot products are the hot path.
                    embedding: new Float32Array(face.embedding),
                    isBadFace: isBadFace(face),
                };
            }
        }
    }
}

const sortFacesNewestOnesFirst = (
    faces: ClusterFace[],
    localFiles: EnteFile[],
) => {
    const localFileByID = new Map(localFiles.map((f) => [f.id, f]));
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

const isBadFace = (face: Face) =>
    face.blur < 50 ||
    (face.blur < 200 && face.score < 0.85) ||
    isSidewaysFace(face);

const isSidewaysFace = (face: Face) =>
    faceDirection(face.detection) != "straight";

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

    // Common incremental case; avoids the O(n²) loop.
    if (!unclusteredFaces.length) {
        onProgress({ completed: batch.length, total: batch.length });
        return;
    }

    // Existing clusters must come first because matches only look backward.
    const faces = clusteredFaces.concat(unclusteredFaces);

    for (const [i, fi] of faces.entries()) {
        if (i % 100 == 0) {
            onProgress({ completed: i, total: batch.length });
            // Yield so clustering does not block other worker requests.
            await wait(0);
        }

        if (state.faceIDToClusterID.has(fi.faceID)) continue;

        const rejectedClusters = rejectedClusterIDsForFaceID.get(fi.faceID);

        let nnIndex: number | undefined;
        let nnCosineSimilarity = 0;
        for (let j = i - 1; j >= 0; j--) {
            // O(n²): keep this loop minimal.
            const fj = faces[j]!;

            // Embeddings are normalized, so this is cosine similarity.
            const csim = dotProduct(fi.embedding, fj.embedding);
            if (csim <= nnCosineSimilarity) continue;

            const threshold = fj.isBadFace ? 0.84 : 0.76;
            if (csim < threshold) continue;

            // Never return a face to a cluster the user rejected.
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

export const reconcileClusters = async (
    clusters: FaceCluster[],
    modifiedClusterIDs: Set<string>,
    masterKey: string,
) => {
    const clusterByID = new Map(clusters.map((c) => [c.id, c]));

    const cgroups = await savedCGroups();

    const changedCGroups = cgroups
        .map((cgroup) => {
            for (const cluster of cgroup.data.assigned) {
                if (modifiedClusterIDs.has(cluster.id)) {
                    return {
                        ...cgroup,
                        data: {
                            ...cgroup.data,
                            // Missing assignments must fail; dropping them
                            // would overwrite remote data.
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

    if (changedCGroups.length) {
        await updateOrCreateUserEntities("cgroup", changedCGroups, masterKey);
        log.info(`Updated ${changedCGroups.length} remote cgroups`);
    }

    const isRemoteClusterID = new Set<string>();
    for (const cgroup of cgroups) {
        for (const cluster of cgroup.data.assigned)
            isRemoteClusterID.add(cluster.id);
    }

    await saveFaceClusters(
        clusters.filter(({ id }) => !isRemoteClusterID.has(id)),
    );

    if (changedCGroups.length) await pullUserEntities("cgroup", masterKey);
};
