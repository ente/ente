import { uniqueFilesByID } from "ente-gallery/utils/file";
import { suppressSharedFilesSavedByUser } from "../../media/media-files";
import type { GalleryDestination } from "../../navigation/navigation-state";
import type { GalleryState } from "../../reducer";
import type { GalleryView } from "../view-types";

export const derivePeopleView = (
    peopleState: GalleryState["peopleState"],
    tempDeletedFileIDs: GalleryState["tempDeletedFileIDs"],
    tempHiddenFileIDs: GalleryState["tempHiddenFileIDs"],
    selectedPersonIDs: string[] = [],
    retainedPersonIDs: string[] = [],
): {
    view: Extract<GalleryView, { type: "people" }>;
    extraVisiblePersonIDs: string[];
} => {
    const people = (peopleState?.people ?? [])
        .map((person) => ({
            ...person,
            fileIDs: person.fileIDs.filter(
                (id) =>
                    !tempDeletedFileIDs.has(id) && !tempHiddenFileIDs.has(id),
            ),
        }))
        .filter((person) => person.fileIDs.length > 0);
    const byID = new Map(people.map((person) => [person.id, person]));
    const visibleIDs = new Set(
        peopleState?.visiblePeople.map((person) => person.id),
    );
    const extraVisiblePersonIDs = [
        ...new Set([...retainedPersonIDs, ...selectedPersonIDs]),
    ].filter((id) => byID.has(id) && !visibleIDs.has(id));
    const activePeople = [...new Set(selectedPersonIDs)].flatMap((id) => {
        const person = byID.get(id);
        return person ? [person] : [];
    });
    const view = {
        type: "people" as const,
        people,
        visiblePeople: [
            ...people.filter((person) => visibleIDs.has(person.id)),
            ...extraVisiblePersonIDs.map((id) => byID.get(id)!),
        ],
        activePeople,
    };
    return { view, extraVisiblePersonIDs };
};

export const derivePeopleFilteredFiles = (
    collectionFiles: GalleryState["collectionFiles"],
    hiddenFileIDs: GalleryState["hiddenFileIDs"],
    view: Extract<GalleryView, { type: "people" }>,
    currentUserID: number | undefined,
) => {
    const sets = view.activePeople.map((person) => new Set(person.fileIDs));
    return uniqueFilesByID(
        suppressSharedFilesSavedByUser(
            collectionFiles.filter(
                (file) =>
                    sets.length > 0 &&
                    !hiddenFileIDs.has(file.id) &&
                    sets.every((ids) => ids.has(file.id)),
            ),
            currentUserID,
            undefined,
        ),
    );
};

export const resolvePeopleDestination = (
    library: GalleryState,
    destination: GalleryDestination,
): GalleryDestination => {
    // Absence of a snapshot means loading, not that selected people disappeared.
    if (!library.peopleState) return destination;
    const existingIDs = new Set(
        library.peopleState.people
            .filter((person) =>
                person.fileIDs.some(
                    (id) =>
                        !library.tempDeletedFileIDs.has(id) &&
                        !library.tempHiddenFileIDs.has(id),
                ),
            )
            .map((person) => person.id),
    );
    const personIDs = destination.personIDs?.filter((id) =>
        existingIDs.has(id),
    );
    const extraVisiblePersonIDs = destination.extraVisiblePersonIDs?.filter(
        (id) => existingIDs.has(id),
    );
    if (
        personIDs?.length === destination.personIDs?.length &&
        extraVisiblePersonIDs?.length ===
            destination.extraVisiblePersonIDs?.length
    )
        return destination;
    return {
        ...destination,
        personIDs,
        extraVisiblePersonIDs,
        peopleSelectionMode:
            !!destination.peopleSelectionMode && (personIDs?.length ?? 0) > 1,
    };
};
