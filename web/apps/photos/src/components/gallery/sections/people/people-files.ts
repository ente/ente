import { uniqueFilesByID } from "ente-gallery/utils/file";
import type { Person } from "ente-new/photos/services/ml/people";
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
    const activePeople = (
        selectedPersonIDs[0] && byID.has(selectedPersonIDs[0])
            ? [...new Set(selectedPersonIDs)]
            : []
    ).flatMap((id) => {
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
        personIDsByFileID:
            peopleState?.personIDsByFileID ?? new Map<number, Set<string>>(),
        unassignedFaceFileIDs:
            peopleState?.unassignedFaceFileIDs ?? new Set<number>(),
    };
    return { view, extraVisiblePersonIDs };
};

export const derivePeopleFilteredFiles = (
    collectionFiles: GalleryState["collectionFiles"],
    hiddenFileIDs: GalleryState["hiddenFileIDs"],
    view: Extract<GalleryView, { type: "people" }>,
    currentUserID: number | undefined,
    onlyThem = false,
) => {
    const sets = view.activePeople.map((person) => new Set(person.fileIDs));
    const selectedIDs = new Set(view.activePeople.map((person) => person.id));
    return uniqueFilesByID(
        suppressSharedFilesSavedByUser(
            collectionFiles.filter(
                (file) =>
                    sets.length > 0 &&
                    !hiddenFileIDs.has(file.id) &&
                    sets.every((ids) => ids.has(file.id)) &&
                    (!onlyThem ||
                        (!view.unassignedFaceFileIDs.has(file.id) &&
                            [
                                ...(view.personIDsByFileID.get(file.id) ?? []),
                            ].every((id) => selectedIDs.has(id)))),
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
    const personIDs =
        destination.personIDs?.[0] && existingIDs.has(destination.personIDs[0])
            ? destination.personIDs.filter((id) => existingIDs.has(id))
            : destination.personIDs
              ? []
              : undefined;
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
        peopleOnlyThem:
            personIDs?.length === destination.personIDs?.length
                ? destination.peopleOnlyThem
                : undefined,
    };
};

// Keep applied filters available even when their intersection becomes empty.
export const peopleFilterSuggestions = (
    people: Person[],
    activePeople: Person[],
    files: GalleryState["collectionFiles"],
): Person[] => {
    const primaryID = activePeople[0]?.id;
    if (!primaryID) return [];
    const selected = activePeople.slice(1);
    const selectedIDs = new Set(activePeople.map((person) => person.id));
    const fileIDs = new Set(files.map((file) => file.id));
    const suggestions = people
        .filter(
            (person) =>
                !selectedIDs.has(person.id) &&
                (person.type !== "cgroup" || !person.isHidden),
        )
        .map((person) => ({
            person,
            count: new Set(person.fileIDs.filter((id) => fileIDs.has(id))).size,
        }))
        .filter(({ count }) => count > 0)
        .sort(
            (a, b) =>
                b.count - a.count ||
                (a.person.name ?? "").localeCompare(b.person.name ?? "") ||
                a.person.id.localeCompare(b.person.id),
        );
    return [...selected, ...suggestions.map(({ person }) => person)];
};
