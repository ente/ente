import type { EnteFile } from "ente-media/file";
import type { PeopleState, Person } from "ente-new/photos/services/ml/people";
import { afterEach, expect, test, vi } from "vitest";
import { emptySelection } from "../src/components/gallery/media/file-selection";
import {
    initialNavigationState,
    navigationReducer,
} from "../src/components/gallery/navigation/navigation-state";
import { initialGalleryState } from "../src/components/gallery/reducer";
import {
    derivePeopleFilteredFiles,
    derivePeopleView,
    resolvePeopleDestination,
} from "../src/components/gallery/sections/people/people-files";
import { createPeoplePress } from "../src/components/gallery/sections/people/people-press";
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
        peopleSelectionMode: true,
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
    expect(removed).toMatchObject({
        personIDs: ["john"],
        peopleSelectionMode: false,
    });
    expect(
        resolvePeopleDestination(
            { ...library, peopleState: { ...peopleState, people: [] } },
            destination,
        ).personIDs,
    ).toEqual([]);
});

test("holds retain the current person; toggles apply immediately; Escape preserves results", () => {
    let state = navigationReducer(initialNavigationState, {
        type: "showPerson",
        personID: "john",
    });
    state = navigationReducer(state, {
        type: "beginPeopleSelection",
        personID: "john",
    });
    expect(state.destination).toMatchObject({
        personIDs: ["john"],
        peopleSelectionMode: true,
    });
    state = navigationReducer(state, {
        type: "togglePerson",
        personID: "alice",
    });
    expect(state.destination.personIDs).toEqual(["john", "alice"]);
    state = navigationReducer(state, { type: "exitPeopleSelection" });
    expect(state.destination).toMatchObject({
        personIDs: ["john", "alice"],
        peopleSelectionMode: false,
    });
    state = navigationReducer(state, { type: "showPerson", personID: "alice" });
    expect(state.destination.personIDs).toEqual(["alice"]);
    state = navigationReducer(state, {
        type: "beginPeopleSelection",
        personID: "john",
    });
    state = navigationReducer(state, {
        type: "togglePerson",
        personID: "john",
    });
    expect(state.destination).toMatchObject({
        personIDs: ["alice"],
        peopleSelectionMode: false,
    });
    state = navigationReducer(state, {
        type: "beginPeopleSelection",
        personID: "alice",
    });
    state = navigationReducer(state, {
        type: "togglePerson",
        personID: "alice",
    });
    expect(state.destination.personIDs).toEqual([]);
    state = navigationReducer(state, { type: "showPeople" });
    expect(state.destination).toEqual({ section: "people" });
});

test("retaining a newly visible unnamed cluster does not end the initial hold mode", () => {
    let state = navigationReducer(initialNavigationState, {
        type: "beginPeopleSelection",
        personID: "unnamed",
    });
    state = navigationReducer(state, {
        type: "retainPeople",
        personIDs: ["unnamed"],
        extraVisiblePersonIDs: ["unnamed"],
    });
    expect(state.destination.peopleSelectionMode).toBe(true);
});

afterEach(() => vi.useRealTimers());
test("hold fires at 450ms and consumes exactly one release click", () => {
    vi.useFakeTimers();
    const hold = vi.fn();
    const press = createPeoplePress(hold);
    press.start(0, 0);
    vi.advanceTimersByTime(449);
    expect(hold).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(hold).toHaveBeenCalledOnce();
    press.end();
    expect(press.consumeClick()).toBe(true);
    expect(press.consumeClick()).toBe(false);
});
test.each(["move", "cancel", "end"] as const)(
    "%s cancels a pending hold",
    (action) => {
        vi.useFakeTimers();
        const hold = vi.fn();
        const press = createPeoplePress(hold);
        press.start(0, 0);
        if (action === "move") press.move(9, 0);
        else press[action]();
        vi.advanceTimersByTime(500);
        expect(hold).not.toHaveBeenCalled();
        expect(press.consumeClick()).toBe(action !== "end");
    },
);
test("small pointer jitter does not cancel a hold; a new press resets cancellation", () => {
    vi.useFakeTimers();
    const hold = vi.fn();
    const press = createPeoplePress(hold);
    press.start(0, 0);
    press.move(4, 4);
    vi.advanceTimersByTime(450);
    expect(hold).toHaveBeenCalledOnce();
    press.cancel();
    press.start(0, 0);
    press.end();
    expect(press.consumeClick()).toBe(false);
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
