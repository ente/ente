import { uniqueFilesByID } from "ente-gallery/utils/file";
import type { Person } from "ente-new/photos/services/ml/people";
import { suppressSharedFilesSavedByUser } from "./media-files";
import type { GalleryDestination } from "./navigation-state";
import type { GalleryState } from "./reducer";
import type { GalleryView } from "./view-types";
export const derivePeopleView = (
    peopleState: GalleryState["peopleState"],
    tempDeletedFileIDs: GalleryState["tempDeletedFileIDs"],
    tempHiddenFileIDs: GalleryState["tempHiddenFileIDs"],
    selectedPersonID: string | undefined,
    extraVisiblePerson: Person | undefined,
): {
    view: Extract<GalleryView, { type: "people" }>;
    extraVisiblePerson: Person | undefined;
} => {
    let people = peopleState?.people ?? [];
    let visiblePeople = peopleState?.visiblePeople ?? [];
    if (tempDeletedFileIDs.size + tempHiddenFileIDs.size > 0) {
        const filterTemp = (ps: Person[]) =>
            ps
                .map((p) => ({
                    ...p,
                    fileIDs: p.fileIDs.filter(
                        (id) =>
                            !tempDeletedFileIDs.has(id) &&
                            !tempHiddenFileIDs.has(id),
                    ),
                }))
                .filter((p) => p.fileIDs.length > 0);
        people = filterTemp(people);
        visiblePeople = filterTemp(visiblePeople);
    }

    // Keep a selected small cluster visible until the user leaves this view.
    if (extraVisiblePerson) {
        if (!people.find((p) => p.id == extraVisiblePerson?.id))
            extraVisiblePerson = undefined;
    }

    const findByIDIn = (ps: Person[]) =>
        ps.find((p) => p.id == selectedPersonID);
    let activePerson = findByIDIn(visiblePeople);
    if (!activePerson) {
        activePerson = findByIDIn(people);
        if (activePerson) {
            extraVisiblePerson = activePerson;
        }
    }

    const view = {
        type: "people" as const,
        people,
        visiblePeople: extraVisiblePerson
            ? visiblePeople.concat([extraVisiblePerson])
            : visiblePeople,
        activePerson,
    };

    return { view, extraVisiblePerson };
};
export const derivePeopleFilteredFiles = (
    collectionFiles: GalleryState["collectionFiles"],
    hiddenFileIDs: GalleryState["hiddenFileIDs"],
    view: Extract<GalleryView, { type: "people" }>,
    currentUserID: number | undefined,
) => {
    const pfSet = new Set(view.activePerson?.fileIDs ?? []);
    return uniqueFilesByID(
        suppressSharedFilesSavedByUser(
            collectionFiles.filter((f) => {
                if (!pfSet.has(f.id)) return false;
                if (hiddenFileIDs.has(f.id)) return false;
                return true;
            }),
            currentUserID,
            undefined,
        ),
    );
};

export const resolvePeopleDestination = (
    library: GalleryState,
    destination: GalleryDestination,
): GalleryDestination => {
    const exists = (id: string | undefined) =>
        id !== undefined &&
        library.peopleState?.people.some(
            (person) =>
                person.id === id &&
                person.fileIDs.some(
                    (fileID) =>
                        !library.tempDeletedFileIDs.has(fileID) &&
                        !library.tempHiddenFileIDs.has(fileID),
                ),
        );
    const personID = exists(destination.personID)
        ? destination.personID
        : undefined;
    const extraVisiblePersonID = exists(destination.extraVisiblePersonID)
        ? destination.extraVisiblePersonID
        : undefined;
    return personID === destination.personID &&
        extraVisiblePersonID === destination.extraVisiblePersonID
        ? destination
        : { ...destination, personID, extraVisiblePersonID };
};
