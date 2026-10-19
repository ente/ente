import { assertionFailed } from "ente-base/assert";
import log from "ente-base/log";
import type { EnteFile } from "ente-media/file";
import { fileCreationPhotoSortTime } from "ente-media/file-metadata";
import { randomSample } from "ente-utils/array";
import { computeNormalCollectionFilesFromSaved } from "../file";
import {
    savedCGroups,
    updateOrCreateUserEntities,
    type CGroup,
} from "../user-entity";
import type { FaceCluster } from "./cluster";
import { savedFaceClusters, savedFaceIndexes, saveFaceClusters } from "./db";
import { fileIDFromFaceID } from "./face";
import {
    savedRejectedClustersForCGroup,
    saveRejectedClustersForCGroup,
} from "./kvdb";
import { dotProduct } from "./math";

// Only cgroups sync; interacting with a local cluster promotes it.
export interface CGroupUserEntityData {
    // Empty and undefined both mean unnamed; write empty when clearing.
    name?: string | undefined;
    // These arrays are unordered sets on the wire.
    assigned: FaceCluster[];
    rejectedFaceIDs: string[];
    manuallyAssigned: number[];
    isHidden: boolean;
    avatarFaceID?: string | undefined;
    isPinned?: boolean | undefined;
    // Desktop does not use this yet, but mobile does.
    hideFromMemories?: boolean | undefined;
}

export type Person = (
    | { type: "cgroup"; cgroup: CGroup; isHidden: boolean }
    | { type: "cluster"; cluster: FaceCluster }
) & {
    id: string;
    name: string | undefined;
    fileIDs: number[];
    isPinned: boolean;
    hideFromMemories: boolean;
    displayFaceID: string;
    displayFaceFile: EnteFile;
};

export type CGroupPerson = Exclude<Person, { type: "cluster" }>;

export type ClusterPerson = Exclude<Person, { type: "cgroup" }>;

export type NamedPerson = Person & { name: string };

export interface PreviewableFace {
    faceID: string;
    file: EnteFile;
}

export interface PeopleState {
    people: Person[];
    visiblePeople: Person[];
    personByFaceID: Map<string, Person>;
}

export const reconstructPeopleState = async (): Promise<PeopleState> => {
    const normalCollectionFiles = await computeNormalCollectionFilesFromSaved();
    const fileByID = new Map(normalCollectionFiles.map((f) => [f.id, f]));

    // Hidden and deleted files deliberately leave holes in this map.
    const personFaceByID = new Map<
        string,
        { faceID: string; file: EnteFile; score: number; sortTime: number }
    >();

    const faceIndexes = await savedFaceIndexes();
    for (const { faces } of faceIndexes) {
        for (const { faceID, score } of faces) {
            const fileID = fileIDFromFaceID(faceID);
            if (!fileID) continue;
            const file = fileByID.get(fileID);
            if (!file) continue;
            personFaceByID.set(faceID, {
                faceID,
                file,
                score,
                sortTime: fileCreationPhotoSortTime(file),
            });
        }
    }

    const personFacesSortedNewestFirst = (faceIDs: string[]) =>
        faceIDs
            .map((faceID) => personFaceByID.get(faceID))
            .filter((pf) => !!pf)
            .sort((a, b) => {
                const at = a.sortTime;
                const bt = b.sortTime;
                return bt == at ? b.score - a.score : bt - at;
            });

    type Interim = (Person | undefined)[];

    const cgroups = await savedCGroups();
    const cgroupPeople: Interim = cgroups.map((cgroup) => {
        const { id, data } = cgroup;
        const { name, assigned } = data;

        let isHidden = data.isHidden;

        // Older mobile clients encoded ignored people in the name.
        if (!name || name == "(hidden)" || name == "(ignored)") isHidden = true;

        let assignedFaceIDs: string[][];
        if (data.rejectedFaceIDs.length == 0) {
            assignedFaceIDs = assigned.map(({ faces }) => faces);
        } else {
            const rejectedFaceIDs = new Set(data.rejectedFaceIDs);
            assignedFaceIDs = assigned.map(({ faces }) =>
                faces.filter((id) => !rejectedFaceIDs.has(id)),
            );
        }

        const faces = personFacesSortedNewestFirst(assignedFaceIDs.flat());

        const mostRecentFace = faces[0];
        if (!mostRecentFace) return undefined;

        const fileIDsSet = new Set(faces.map((f) => f.file.id));
        for (const fileID of data.manuallyAssigned) {
            if (fileByID.has(fileID)) fileIDsSet.add(fileID);
        }
        const fileIDs = [...fileIDsSet];

        let avatarFile: EnteFile | undefined;
        const avatarFaceID = resolvedAvatarFaceID(data.avatarFaceID);
        if (avatarFaceID) {
            const avatarFileID = fileIDFromFaceID(avatarFaceID);
            if (avatarFileID) avatarFile = fileByID.get(avatarFileID);
        }

        let displayFaceID: string;
        let displayFaceFile: EnteFile;
        if (avatarFaceID && avatarFile) {
            displayFaceID = avatarFaceID;
            displayFaceFile = avatarFile;
        } else {
            displayFaceID = mostRecentFace.faceID;
            displayFaceFile = mostRecentFace.file;
        }

        const isPinned = data.isPinned ?? false;
        const hideFromMemories = data.hideFromMemories ?? false;

        return {
            type: "cgroup",
            cgroup,
            id,
            name,
            fileIDs,
            displayFaceID,
            displayFaceFile,
            isHidden,
            isPinned,
            hideFromMemories,
        };
    });

    const localClusters = await savedFaceClusters();
    const clusterPeople: Interim = localClusters.map((cluster) => {
        const faces = personFacesSortedNewestFirst(cluster.faces);

        const mostRecentFace = faces[0];
        if (!mostRecentFace) return undefined;

        return {
            type: "cluster",
            cluster,
            id: cluster.id,
            name: undefined,
            fileIDs: [...new Set(faces.map((f) => f.file.id))],
            displayFaceID: mostRecentFace.faceID,
            displayFaceFile: mostRecentFace.file,
            isPinned: false,
            hideFromMemories: false,
        };
    });

    const sorted = (ps: Interim) =>
        ps
            .filter((c): c is Person => !!c)
            .sort((a, b) =>
                a.isPinned == b.isPinned
                    ? b.fileIDs.length - a.fileIDs.length
                    : a.isPinned
                      ? -1
                      : 1,
            );

    const people = sorted(cgroupPeople).concat(sorted(clusterPeople));

    const visiblePeople = people.filter((p) => {
        switch (p.type) {
            case "cgroup":
                if (p.isHidden) return false;
                break;

            case "cluster":
                if (p.cluster.faces.length < 10) return false;
                break;
        }

        return true;
    });

    const personByFaceID = new Map<string, Person>();
    for (const person of people) {
        const faceIDs =
            person.type == "cgroup"
                ? person.cgroup.data.assigned.map((c) => c.faces).flat()
                : person.cluster.faces;
        for (const faceID of faceIDs) {
            personByFaceID.set(faceID, person);
        }
    }

    return { people, visiblePeople, personByFaceID };
};

// Older mobile clients stored avatarFileID in this field.
const resolvedAvatarFaceID = (avatarFaceID: string | undefined) =>
    avatarFaceID?.split("_").length == 1 ? undefined : avatarFaceID;

export const filterNamedPeople = (people: Person[]): NamedPerson[] => {
    const namedPeople: NamedPerson[] = [];
    for (const person of people) {
        const name = person.name;
        if (name) {
            namedPeople.push({ ...person, name });
        }
    }
    return namedPeople;
};

export type PreviewableCluster = FaceCluster & {
    previewFaces: PreviewableFace[];
};

export interface PersonSuggestionsAndChoices {
    choices: (PreviewableCluster & { fixed?: boolean; assigned: boolean })[];
    suggestions: PreviewableCluster[];
}

export const _suggestionsAndChoicesForPerson = async (
    person: CGroupPerson,
    currentUserID: number,
): Promise<PersonSuggestionsAndChoices> => {
    const startTime = Date.now();

    const rejectedFaceIDs = new Set(person.cgroup.data.rejectedFaceIDs);
    const personClusters = person.cgroup.data.assigned.map((cluster) => ({
        ...cluster,
        faces: cluster.faces.filter((id) => !rejectedFaceIDs.has(id)),
    }));

    const rejectedClusterIDs = new Set(
        await savedRejectedClustersForCGroup(person.cgroup.id),
    );

    const localClusters = await savedFaceClusters();
    const faceIndexes = await savedFaceIndexes();

    const embeddingByFaceID = new Map(
        faceIndexes
            .map(({ faces }) =>
                faces.map(
                    (f) => [f.faceID, new Float32Array(f.embedding)] as const,
                ),
            )
            .flat(),
    );

    const personFaceEmbeddings = personClusters
        .map(({ faces }) => faces.map((id) => embeddingByFaceID.get(id)))
        .flat()
        .filter((e) => !!e);

    // Bound the quadratic pairwise comparison cost.
    const sampledPersonEmbeddings = randomSample(personFaceEmbeddings, 50);

    const strictMedianSimilarityThreshold = 0.48;
    const relaxedMedianSimilarityThreshold = 0.46;

    const multiFaceClusters: FaceCluster[] = [];
    const singletonClusters: FaceCluster[] = [];
    const rejectedClusters: FaceCluster[] = [];
    for (const cluster of localClusters) {
        const { id, faces } = cluster;

        // Check rejection first so remote singleton rejections remain visible.
        if (rejectedClusterIDs.has(id)) {
            rejectedClusters.push(cluster);
            continue;
        }

        if (faces.length < 2) {
            singletonClusters.push(cluster);
            continue;
        }
        multiFaceClusters.push(cluster);
    }

    const scoreClustersByMedianSimilarity = (clusters: FaceCluster[]) => {
        const clustersAndSimilarity: [FaceCluster, number][] = [];
        for (const cluster of clusters) {
            const { faces } = cluster;

            const sampledOtherEmbeddings = randomSample(faces, 50)
                .map((id) => embeddingByFaceID.get(id))
                .filter((e) => !!e);

            const csims: number[] = [];
            for (const other of sampledOtherEmbeddings) {
                for (const embedding of sampledPersonEmbeddings) {
                    csims.push(dotProduct(embedding, other));
                }
            }
            csims.sort();

            if (csims.length == 0) continue;

            // Median similarity dampens a few misleading face pairs.
            const medianSim = csims[Math.floor(csims.length / 2)]!;
            clustersAndSimilarity.push([cluster, medianSim]);
        }
        clustersAndSimilarity.sort(([, a], [, b]) => b - a);
        return clustersAndSimilarity;
    };

    const selectCandidateClusters = ({
        candidates,
        minMedianSimilarity,
    }: {
        candidates: [FaceCluster, number][];
        minMedianSimilarity: number;
    }) =>
        candidates
            .filter(
                ([, medianSimilarity]) =>
                    medianSimilarity > minMedianSimilarity,
            )
            .map(([cluster]) => cluster);

    const multiFaceCandidateClustersAndSimilarity =
        scoreClustersByMedianSimilarity(multiFaceClusters);
    let suggestionMode = "strict_non_singleton";
    let suggestedClusters = selectCandidateClusters({
        candidates: multiFaceCandidateClustersAndSimilarity,
        minMedianSimilarity: strictMedianSimilarityThreshold,
    });
    if (suggestedClusters.length == 0) {
        suggestionMode = "relaxed_non_singleton";
        suggestedClusters = selectCandidateClusters({
            candidates: multiFaceCandidateClustersAndSimilarity,
            minMedianSimilarity: relaxedMedianSimilarityThreshold,
        });
    }
    // Singleton clusters are the final fallback.
    if (suggestedClusters.length == 0) {
        suggestionMode = "strict_with_singletons";
        const singletonCandidateClustersAndSimilarity =
            scoreClustersByMedianSimilarity(singletonClusters);
        suggestedClusters = selectCandidateClusters({
            candidates: singletonCandidateClustersAndSimilarity,
            minMedianSimilarity: strictMedianSimilarityThreshold,
        });
    }

    const normalCollectionFiles =
        await computeNormalCollectionFilesFromSaved(currentUserID);
    const fileByID = new Map(normalCollectionFiles.map((f) => [f.id, f]));

    const toPreviewable = (cluster: FaceCluster) => {
        const previewFaces: PreviewableFace[] = [];
        for (const faceID of cluster.faces) {
            const fileID = fileIDFromFaceID(faceID);
            if (!fileID) {
                assertionFailed();
                continue;
            }

            const file = fileByID.get(fileID);
            if (!file) {
                continue;
            }

            previewFaces.push({ file, faceID });

            if (previewFaces.length == 4) break;
        }

        if (previewFaces.length == 0) return undefined;

        return { ...cluster, previewFaces };
    };

    const toPreviewableList = (clusters: FaceCluster[]) =>
        clusters.map(toPreviewable).filter((p) => !!p);

    const sortBySize = (entries: { faces: unknown[] }[]) =>
        entries.sort((a, b) => b.faces.length - a.faces.length);

    const assignedChoices = toPreviewableList(personClusters).map((p) => ({
        ...p,
        assigned: true,
    }));

    sortBySize(assignedChoices);

    const rejectedChoices = toPreviewableList(rejectedClusters).map((p) => ({
        ...p,
        assigned: false,
    }));

    const firstChoice = { ...assignedChoices[0]!, fixed: true };
    const restChoices = assignedChoices.slice(1).concat(rejectedChoices);
    sortBySize(restChoices);

    const choices = [firstChoice, ...restChoices];

    const suggestions = toPreviewableList(suggestedClusters.slice(0, 80));

    log.info(
        `Generated ${suggestions.length} suggestions for ${person.id} using ${suggestionMode} (${Date.now() - startTime} ms)`,
    );

    return { choices, suggestions };
};

export type PersonSuggestionUpdates = Map<
    string,
    "assign" | "rejectSuggestion" | "rejectSavedChoice" | "reset"
>;

export const _applyPersonSuggestionUpdates = async (
    cgroup: CGroup,
    updates: PersonSuggestionUpdates,
    masterKey: string,
) => {
    const localClusters = await savedFaceClusters();

    let assignedClusters = [...cgroup.data.assigned];
    let rejectedClusterIDs = await savedRejectedClustersForCGroup(cgroup.id);
    let newlyRejectedFaceIDs: string[] = [];

    let assignUpdateCount = 0;
    let rejectUpdateCount = 0;

    const clusterWithID = (clusterID: string) =>
        localClusters.find((c) => c.id == clusterID)!;

    const assign = (clusterID: string) => {
        const cluster = clusterWithID(clusterID);
        assignedClusters.push(cluster);
        assignUpdateCount += 1;
    };

    const unassignIfNeeded = (clusterID: string) => {
        if (assignedClusters.find(({ id }) => id == clusterID)) {
            const [updatedAssignedClusters, cluster] = assignedClusters.reduce<
                [FaceCluster[], FaceCluster | undefined]
            >(
                ([clusters, foundCluster], c) => {
                    if (c.id == clusterID) return [clusters, c];
                    clusters.push(c);
                    return [clusters, foundCluster];
                },
                [[], undefined],
            );

            assignedClusters = updatedAssignedClusters;
            assignUpdateCount += 1;
            // Assigned clusters came from remote; restore them locally first.
            localClusters.push(cluster!);
        }
    };

    const rejectClusterLocal = (clusterID: string) => {
        rejectedClusterIDs.push(clusterID);
        rejectUpdateCount += 1;
    };

    const rejectFacesRemote = (clusterID: string) => {
        const cluster = clusterWithID(clusterID);
        newlyRejectedFaceIDs = newlyRejectedFaceIDs.concat(cluster.faces);
    };

    const unrejectIfNeeded = (clusterID: string) => {
        if (rejectedClusterIDs.includes(clusterID)) {
            rejectedClusterIDs = rejectedClusterIDs.filter(
                (id) => id != clusterID,
            );
            rejectUpdateCount += 1;
        }
    };

    for (const [clusterID, assigned] of updates.entries()) {
        switch (assigned) {
            case "assign":
                assign(clusterID);
                unrejectIfNeeded(clusterID);
                break;

            case "rejectSuggestion":
                unassignIfNeeded(clusterID);
                rejectClusterLocal(clusterID);
                break;

            case "rejectSavedChoice":
                unassignIfNeeded(clusterID);
                rejectClusterLocal(clusterID);
                rejectFacesRemote(clusterID);
                break;

            case "reset":
                unassignIfNeeded(clusterID);
                unrejectIfNeeded(clusterID);
                break;
        }
    }

    if (assignUpdateCount > 0 || newlyRejectedFaceIDs.length > 0) {
        const assigned = assignedClusters;
        const rejectedFaceIDs =
            cgroup.data.rejectedFaceIDs.concat(newlyRejectedFaceIDs);
        await updateOrCreateUserEntities(
            "cgroup",
            [
                {
                    ...cgroup,
                    data: { ...cgroup.data, assigned, rejectedFaceIDs },
                },
            ],
            masterKey,
        );
        await saveFaceClusters(localClusters);
    }

    if (rejectUpdateCount > 0) {
        await saveRejectedClustersForCGroup(cgroup.id, rejectedClusterIDs);
    }

    log.info(
        `Updated ${assignUpdateCount} assigns and ${rejectUpdateCount} rejects for ${cgroup.id}`,
    );
};
