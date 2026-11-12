import type { CGroup } from "../user-entity";
import type { LocalFaceIndex } from "./face";
import type { Person } from "./people";

// Include ignored people, small clusters, and manual assignments even when a
// person has no previewable face. A detected, unassigned face also rules out an
// exact people match.
export const peopleFileMembership = (
    people: Person[],
    faceIndexes: LocalFaceIndex[],
    cgroups: CGroup[],
) => {
    const personIDsByFileID = new Map<number, Set<string>>();
    const peopleByFaceID = new Map<string, Set<string>>();
    const unassignedFaceFileIDs = new Set<number>();
    const add = <K>(map: Map<K, Set<string>>, key: K, personID: string) => {
        const ids = map.get(key) ?? new Set<string>();
        ids.add(personID);
        map.set(key, ids);
    };
    for (const person of people) {
        for (const fileID of person.fileIDs)
            add(personIDsByFileID, fileID, person.id);
        if (person.type === "cluster")
            for (const faceID of person.cluster.faces)
                add(peopleByFaceID, faceID, person.id);
    }
    for (const { id, data } of cgroups) {
        const rejected = new Set(data.rejectedFaceIDs);
        for (const cluster of data.assigned)
            for (const faceID of cluster.faces)
                if (!rejected.has(faceID)) add(peopleByFaceID, faceID, id);
        for (const fileID of data.manuallyAssigned)
            add(personIDsByFileID, fileID, id);
    }
    for (const { fileID, faces } of faceIndexes) {
        for (const { faceID } of faces) {
            const ids = peopleByFaceID.get(faceID);
            if (!ids?.size) unassignedFaceFileIDs.add(fileID);
            else for (const id of ids) add(personIDsByFileID, fileID, id);
        }
    }
    return { personIDsByFileID, unassignedFaceFileIDs };
};
