import type { EnteFile } from "ente-media/file";
import type { PeopleState, Person } from "ente-new/photos/services/ml/people";
import { expect, test, vi } from "vitest";
import { emptySelection } from "../src/components/gallery/media/file-selection";
import {
    initialNavigationState,
    navigationReducer,
} from "../src/components/gallery/navigation/navigation-state";
import { initialGalleryState } from "../src/components/gallery/reducer";
import {
    derivePeopleFilteredFiles,
    derivePeopleView,
    peopleFilterSuggestions,
    resolvePeopleDestination,
} from "../src/components/gallery/sections/people/people-files";
import type { SelectedState, SetSelectedState } from "../src/utils/file";
import {
    handleSelectCreator,
    handleSelectCreatorMulti,
} from "../src/utils/photoFrame";

const people = [
    { id: "john", name: "John", fileIDs: [1, 2, 3, 4, 5] },
    { id: "alice", name: "Alice", fileIDs: [2, 3, 4, 5] },
    { id: "unnamed", fileIDs: [3, 4] },
    { id: "other", name: "Other", fileIDs: [6] },
] as Person[];
const peopleState: PeopleState = {
    people,
    visiblePeople: people.filter((p) => p.name),
    personByFaceID: new Map(),
    personIDsByFileID: new Map(),
    unassignedFaceFileIDs: new Set(),
};
const collectionFiles = [1, 2, 3, 4, 5, 6, 2].map((id) => ({
    id,
    ownerID: 1,
    collectionID: 10,
    metadata: { creationTime: id },
})) as EnteFile[];
const library = {
    ...initialGalleryState,
    peopleState,
    collectionFiles,
    hiddenFileIDs: new Set([5]),
};
const results = (
    ids: string[],
    deleted = new Set<number>(),
    hidden = new Set<number>(),
) => {
    const { view } = derivePeopleView(peopleState, deleted, hidden, ids);
    return derivePeopleFilteredFiles(
        collectionFiles,
        library.hiddenFileIDs,
        view,
        1,
    ).map((file) => file.id);
};

test("AND intersects two/three people, deduplicates and preserves visibility and order", () => {
    expect(results(["john"])).toEqual([1, 2, 3, 4]);
    expect(results(["john", "alice"])).toEqual([2, 3, 4]);
    expect(results(["john", "alice", "unnamed"])).toEqual([3, 4]);
    expect(results(["john", "other"])).toEqual([]);
    expect(results([])).toEqual([]);
    expect(results(["john", "alice"], new Set([2]), new Set([3]))).toEqual([4]);
});

test("keeps selected small clusters visible without duplicating them after promotion", () => {
    const { view, extraVisiblePersonIDs } = derivePeopleView(
        peopleState,
        new Set(),
        new Set(),
        ["john", "unnamed", "unnamed"],
    );
    expect(view.activePeople.map((p) => p.id)).toEqual(["john", "unnamed"]);
    expect(extraVisiblePersonIDs).toEqual(["unnamed"]);
    const promoted = derivePeopleView(
        { ...peopleState, visiblePeople: people },
        new Set(),
        new Set(),
        ["john", "unnamed"],
        extraVisiblePersonIDs,
    );
    expect(
        promoted.view.visiblePeople.filter((p) => p.id === "unnamed"),
    ).toHaveLength(1);
});

test("selection survives loading and rename, prunes missing people after refresh", () => {
    const destination = {
        section: "people" as const,
        personIDs: ["john", "alice"],
    };
    expect(
        resolvePeopleDestination(
            { ...library, peopleState: undefined },
            destination,
        ),
    ).toBe(destination);
    expect(
        resolvePeopleDestination(
            {
                ...library,
                peopleState: {
                    ...peopleState,
                    people: people.map((p) => ({ ...p, name: "Renamed" })),
                },
            },
            destination,
        ),
    ).toBe(destination);
    const removed = resolvePeopleDestination(
        { ...library, peopleState: { ...peopleState, people: [people[0]!] } },
        destination,
    );
    expect(removed).toMatchObject({ personIDs: ["john"] });
    expect(
        resolvePeopleDestination(
            { ...library, peopleState: { ...peopleState, people: [] } },
            destination,
        ).personIDs,
    ).toEqual([]);
});

test("row clicks toggle additional people, while sidebar navigation replaces the base person", () => {
    let state = navigationReducer(initialNavigationState, {
        type: "showPerson",
        personID: "john",
    });
    state = navigationReducer(state, {
        type: "togglePerson",
        personID: "alice",
    });
    expect(state.destination.personIDs).toEqual(["john", "alice"]);
    state = navigationReducer(state, {
        type: "togglePerson",
        personID: "john",
    });
    expect(state.destination.personIDs).toEqual(["john", "alice"]);
    state = navigationReducer(state, {
        type: "togglePerson",
        personID: "alice",
    });
    expect(state.destination.personIDs).toEqual(["john"]);
    state = navigationReducer(state, { type: "showPerson", personID: "alice" });
    expect(state.destination.personIDs).toEqual(["alice"]);
    state = navigationReducer(state, { type: "showPeople" });
    expect(state.destination).toEqual({ section: "people" });
    expect(
        navigationReducer(state, { type: "togglePerson", personID: "john" }),
    ).toBe(state);
});

test("filter row recommends only people in visible results and retains applied filters on empty results", () => {
    const { view } = derivePeopleView(peopleState, new Set(), new Set(), [
        "john",
    ]);
    const files = derivePeopleFilteredFiles(
        collectionFiles,
        library.hiddenFileIDs,
        view,
        1,
    );
    expect(
        peopleFilterSuggestions(view.people, view.activePeople, files).map(
            (p) => p.id,
        ),
    ).toEqual(["alice", "unnamed"]);
    expect(
        peopleFilterSuggestions(view.people, [people[0]!, people[1]!], []).map(
            (p) => p.id,
        ),
    ).toEqual(["alice"]);
    expect(peopleFilterSuggestions(view.people, [], files)).toEqual([]);
    const ignored = { ...people[2]!, type: "cgroup", isHidden: true } as Person;
    expect(
        peopleFilterSuggestions([people[0]!, ignored], [people[0]!], files),
    ).toEqual([]);
});

test("removing the base person returns to the overview instead of opening an additional filter", () => {
    const changed = {
        ...library,
        peopleState: { ...peopleState, people: [people[1]!] },
    };
    const destination = {
        section: "people" as const,
        personIDs: ["john", "alice"],
    };
    expect(resolvePeopleDestination(changed, destination).personIDs).toEqual(
        [],
    );
    expect(
        derivePeopleView(
            changed.peopleState,
            new Set(),
            new Set(),
            destination.personIDs,
        ).view.activePeople,
    ).toEqual([]);
});

test("photo selection is scoped to the whole combination, including date/range selection", () => {
    let selected: SelectedState = emptySelection;
    const setSelected: SetSelectedState = (update) => {
        selected = typeof update === "function" ? update(selected) : update;
    };
    handleSelectCreator(
        setSelected,
        "people",
        1,
        undefined,
        ["john", "alice"],
        vi.fn(),
    )({ id: 2, ownerID: 1 })(true);
    expect(selected).toMatchObject({
        count: 1,
        context: { mode: "people", personIDs: ["john", "alice"] },
    });
    handleSelectCreatorMulti(setSelected, "people", 1, undefined, [
        "john",
        "unnamed",
    ])([
        { id: 3, ownerID: 1 },
        { id: 4, ownerID: 1 },
    ])(true);
    expect(selected.count).toBe(2);
    expect(selected[2]).toBeUndefined();
    expect(selected.context).toEqual({
        mode: "people",
        personIDs: ["john", "unnamed"],
    });
});
