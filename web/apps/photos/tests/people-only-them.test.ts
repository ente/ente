import type { EnteFile } from "ente-media/file";
import type { LocalFaceIndex } from "ente-new/photos/services/ml/face";
import type { PeopleState, Person } from "ente-new/photos/services/ml/people";
import { peopleFileMembership } from "ente-new/photos/services/ml/people-membership";
import type { CGroup } from "ente-new/photos/services/user-entity";
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
    resolvePeopleDestination,
} from "../src/components/gallery/sections/people/people-files";
import type { SelectedState, SetSelectedState } from "../src/utils/file";
import {
    handleSelectCreator,
    handleSelectCreatorMulti,
} from "../src/utils/photoFrame";

const group = (
    id: string,
    faces: string[],
    manuallyAssigned: number[] = [],
    rejectedFaceIDs: string[] = [],
) =>
    ({
        id,
        data: {
            assigned: [{ id, faces }],
            manuallyAssigned,
            rejectedFaceIDs,
            isHidden: id === "ignored",
        },
    }) as CGroup;
const cgroups = [
    group(
        "john",
        [1, 2, 3, 4, 5, 6, 7, 8].map((id) => `${id}_john`),
    ),
    group(
        "alice",
        [2, 3, 4, 5, 6, 7, 8].map((id) => `${id}_alice`),
    ),
    group("ignored", ["5_other", "4_rejected"], [], ["4_rejected"]),
    group("manual", [], [6]),
];
const people = [
    {
        type: "cgroup",
        id: "john",
        name: "John",
        cgroup: cgroups[0],
        fileIDs: [1, 2, 3, 4, 5, 6, 7, 8],
    },
    {
        type: "cgroup",
        id: "alice",
        name: "Alice",
        cgroup: cgroups[1],
        fileIDs: [2, 3, 4, 5, 6, 7, 8],
    },
    {
        type: "cgroup",
        id: "ignored",
        isHidden: true,
        cgroup: cgroups[2],
        fileIDs: [5],
    },
    {
        type: "cluster",
        id: "unnamed",
        cluster: { id: "unnamed", faces: ["3_unnamed"] },
        fileIDs: [3],
    },
] as Person[];
const extras: Record<number, string[]> = {
    3: ["3_unnamed"],
    4: ["4_rejected"],
    5: ["5_other"],
    7: ["7_unclustered"],
};
const indexes = [1, 2, 3, 4, 5, 6, 7, 8].map((fileID) => ({
    fileID,
    faces: [
        `${fileID}_john`,
        ...(fileID > 1 ? [`${fileID}_alice`] : []),
        ...(extras[fileID] ?? []),
    ].map((faceID) => ({ faceID })),
})) as LocalFaceIndex[];
const membership = peopleFileMembership(people, indexes, cgroups);
const peopleState: PeopleState = {
    people,
    visiblePeople: people.slice(0, 2),
    personByFaceID: new Map(),
    ...membership,
};
const files = [1, 2, 3, 4, 5, 6, 7, 8, 2].map((id) => ({
    id,
    ownerID: 1,
    collectionID: 10,
    metadata: { creationTime: id },
})) as EnteFile[];
const results = (
    ids: string[],
    onlyThem: boolean,
    deleted = new Set<number>(),
    hidden = new Set<number>(),
) => {
    const { view } = derivePeopleView(peopleState, deleted, hidden, ids);
    return derivePeopleFilteredFiles(
        files,
        new Set([8]),
        view,
        1,
        onlyThem,
    ).map((file) => file.id);
};

test("Only them excludes extra named, ignored, small-cluster, manual and unassigned faces", () => {
    expect(results(["john", "alice"], false)).toEqual([2, 3, 4, 5, 6, 7]);
    expect(results(["john", "alice"], true)).toEqual([2]);
    expect(results(["john"], true)).toEqual([1]);
    expect(results(["john", "alice", "unnamed"], true)).toEqual([3]);
    expect(results(["john", "alice", "ignored"], true)).toEqual([5]);
    expect(results(["john", "unnamed"], true)).toEqual([]);
    expect(results([], true)).toEqual([]);
    expect(results(["john", "alice"], true, new Set([2]))).toEqual([]);
    expect(results(["john", "alice"], true, new Set(), new Set([2]))).toEqual(
        [],
    );
    expect(membership.personIDsByFileID.get(6)).toEqual(
        new Set(["john", "alice", "manual"]),
    );
    expect(membership.unassignedFaceFileIDs).toEqual(new Set([4, 7]));
});

test("multiple faces of a selected person do not count as another person", () => {
    const snapshot = peopleFileMembership(
        [people[0]!],
        [
            {
                fileID: 1,
                faces: [{ faceID: "1_john" }, { faceID: "1_john_again" }],
            },
        ] as LocalFaceIndex[],
        [group("john", ["1_john", "1_john_again"])],
    );
    expect(snapshot.personIDsByFileID.get(1)).toEqual(new Set(["john"]));
    expect(snapshot.unassignedFaceFileIDs.size).toBe(0);
});

test("Only them keeps the combination on toggle, resets on new people, and supports up to four", () => {
    let state = navigationReducer(initialNavigationState, {
        type: "showPerson",
        personID: "john",
    });
    state = navigationReducer(state, {
        type: "togglePerson",
        personID: "alice",
    });
    state = navigationReducer(state, { type: "togglePeopleOnlyThem" });
    expect(state.destination).toMatchObject({
        personIDs: ["john", "alice"],
        peopleOnlyThem: true,
    });
    state = navigationReducer(state, { type: "togglePeopleOnlyThem" });
    expect(state.destination).toMatchObject({
        personIDs: ["john", "alice"],
        peopleOnlyThem: false,
    });
    state = navigationReducer(state, { type: "togglePeopleOnlyThem" });
    state = navigationReducer(state, {
        type: "togglePerson",
        personID: "unnamed",
    });
    expect(state.destination.peopleOnlyThem).toBeUndefined();
    state = navigationReducer(state, {
        type: "togglePerson",
        personID: "fourth",
    });
    state = navigationReducer(state, { type: "togglePeopleOnlyThem" });
    expect(state.destination.peopleOnlyThem).toBe(true);
    state = navigationReducer(state, {
        type: "togglePerson",
        personID: "fifth",
    });
    expect(navigationReducer(state, { type: "togglePeopleOnlyThem" })).toBe(
        state,
    );
    state = navigationReducer(state, { type: "showPerson", personID: "john" });
    expect(state.destination.peopleOnlyThem).toBeUndefined();
    state = navigationReducer(state, { type: "showPeople" });
    expect(navigationReducer(state, { type: "togglePeopleOnlyThem" })).toBe(
        state,
    );
});

test("refresh retains Only them through renames and resets it when a selected person disappears", () => {
    const library = { ...initialGalleryState, peopleState };
    const destination = {
        section: "people" as const,
        personIDs: ["john", "alice"],
        peopleOnlyThem: true,
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
                    people: people.map((person) => ({
                        ...person,
                        name: "Renamed",
                    })),
                },
            },
            destination,
        ),
    ).toBe(destination);
    expect(
        resolvePeopleDestination(
            {
                ...library,
                peopleState: { ...peopleState, people: [people[0]!] },
            },
            destination,
        ),
    ).toMatchObject({ personIDs: ["john"], peopleOnlyThem: undefined });
});

test("photo selection cannot carry over between AND and Only them results", () => {
    let selected: SelectedState = emptySelection;
    const setSelected: SetSelectedState = (update) => {
        selected = typeof update === "function" ? update(selected) : update;
    };
    const ids = ["john", "alice"];
    handleSelectCreatorMulti(
        setSelected,
        "people",
        1,
        undefined,
        ids,
    )([{ id: 3, ownerID: 1 }])(true);
    handleSelectCreator(
        setSelected,
        "people",
        1,
        undefined,
        ids,
        vi.fn(),
        true,
    )({ id: 2, ownerID: 1 })(true);
    expect(selected.count).toBe(1);
    expect(selected[3]).toBeUndefined();
    expect(selected.context).toEqual({
        mode: "people",
        personIDs: ids,
        onlyThem: true,
    });
    handleSelectCreatorMulti(
        setSelected,
        "people",
        1,
        undefined,
        ids,
        false,
    )([{ id: 3, ownerID: 1 }])(true);
    expect(selected[2]).toBeUndefined();
    expect(selected.context).toEqual({
        mode: "people",
        personIDs: ids,
        onlyThem: undefined,
    });
});
