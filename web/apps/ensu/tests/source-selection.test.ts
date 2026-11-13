import assert from "node:assert/strict";
import test from "node:test";
import { ChatSourceSelectionStore } from "../src/services/chat/source-selection.ts";

const available = {
    packIds: ["wiki", "books"],
    noteCollectionIds: ["journal"],
};
const makeStorage = () => {
    const entries = new Map<string, string>();
    const storage: Pick<Storage, "getItem" | "setItem"> = {
        getItem: (key) => entries.get(key) ?? null,
        setItem: (key, value) => entries.set(key, value),
    };
    return storage;
};

void test("legacy migration replaces an already-read default cache", () => {
    const storage = makeStorage();
    storage.setItem("ensu.desktop.enabledKnowledgePacks", '["wiki"]');
    const store = new ChatSourceSelectionStore(storage);
    assert.deepEqual(store.disabledPackIds(), []);
    store.migratePackSettings(available.packIds);
    assert.deepEqual(store.selection(available), {
        packIds: ["wiki"],
        noteCollectionIds: ["journal"],
    });
});

void test("explicit empty legacy choices remain disabled", () => {
    const storage = makeStorage();
    storage.setItem("ensu.desktop.enabledKnowledgePacks", "[]");
    const store = new ChatSourceSelectionStore(storage);
    store.migratePackSettings(available.packIds);
    assert.deepEqual(store.selection(available).packIds, []);
});

void test("empty choices survive restart without repeating legacy migration", () => {
    const storage = makeStorage();
    storage.setItem("ensu.desktop.enabledKnowledgePacks", '["wiki"]');
    const store = new ChatSourceSelectionStore(storage);
    store.migratePackSettings(available.packIds);
    store.setPackEnabled("wiki", false, available.packIds);
    store.setNoteEnabled("journal", false);
    const reopened = new ChatSourceSelectionStore(storage);
    reopened.migratePackSettings(available.packIds);
    assert.deepEqual(reopened.selection(available), {
        packIds: [],
        noteCollectionIds: [],
    });
});

void test("failed migration writes preserve current choices until storage recovers", () => {
    const storage = makeStorage();
    storage.setItem("ensu.desktop.enabledKnowledgePacks", '["wiki"]');
    let writable = false;
    const writeError = new Error("Storage full");
    const errors: unknown[] = [];
    const store = new ChatSourceSelectionStore(
        {
            getItem: storage.getItem,
            setItem: (key, value) => {
                if (!writable) throw writeError;
                storage.setItem(key, value);
            },
        },
        (error) => errors.push(error),
    );
    store.migratePackSettings(available.packIds);
    store.setPackEnabled("wiki", false, available.packIds);
    assert.deepEqual(store.selection(available).packIds, []);
    store.migratePackSettings([...available.packIds]);
    assert.deepEqual(store.selection(available).packIds, []);
    store.setPackEnabled("books", true, available.packIds);
    assert.deepEqual(store.selection(available).packIds, ["books"]);
    assert.ok(errors.includes(writeError));

    writable = true;
    store.migratePackSettings(available.packIds);
    const reopened = new ChatSourceSelectionStore(storage);
    reopened.migratePackSettings(available.packIds);
    assert.deepEqual(reopened.selection(available).packIds, ["books"]);
});

void test("an in-flight send snapshot is unchanged by later settings changes", () => {
    const store = new ChatSourceSelectionStore(makeStorage());
    const snapshot = store.selection(available);
    store.setPackEnabled("wiki", false, available.packIds);
    store.setNoteEnabled("journal", false);
    assert.deepEqual(snapshot, available);
    assert.deepEqual(store.selection(available), {
        packIds: ["books"],
        noteCollectionIds: [],
    });
});
