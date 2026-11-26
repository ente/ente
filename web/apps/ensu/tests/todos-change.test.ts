import assert from "node:assert/strict";
import test from "node:test";
import { todoChanges, type Todo } from "../src/services/todos.ts";

const todo: Todo = {
    id: "read",
    title: "Read the book",
    dueAtMs: null,
    completedAtMs: null,
    version: 1,
};

void test("queued To Do toggles use the version returned by the preceding change", async () => {
    const changes = todoChanges();
    const completed = Promise.withResolvers<Todo>();
    const versions: number[] = [];
    const first = changes.change(todo, (latest) => {
        versions.push(latest.version);
        return completed.promise;
    });
    const second = changes.change(todo, (latest) => {
        versions.push(latest.version);
        assert.equal(latest.completedAtMs, 1);
        return Promise.resolve({ ...latest, completedAtMs: null, version: 3 });
    });
    const third = changes.change(todo, (latest) => {
        versions.push(latest.version);
        assert.equal(latest.completedAtMs, null);
        return Promise.resolve();
    });
    await Promise.resolve();
    assert.deepEqual(versions, [1]);
    completed.resolve({ ...todo, completedAtMs: 1, version: 2 });
    await Promise.all([first, second, third]);
    assert.deepEqual(versions, [1, 2, 3]);
});

void test("a failed To Do change leaves the next change queued", async () => {
    const changes = todoChanges();
    const failure = new Error("change failed");
    const first = changes.change(todo, (): Promise<never> =>
        Promise.reject(failure),
    );
    const second = changes.change(todo, (latest) => {
        assert.equal(latest.version, 1);
        return Promise.resolve();
    });
    await assert.rejects(first, failure);
    await second;
});

void test("queued To Do actions preserve conflicts across external edits", async () => {
    for (const operation of ["delete", "complete"]) {
        for (const changeAfterEdit of [false, true]) {
            const changes = todoChanges();
            const own = { ...todo, version: 2, completedAtMs: 1 };
            await changes.change(todo, () => Promise.resolve(own));
            const gate = Promise.withResolvers<undefined>();
            const blocked = changes.change(
                { ...todo, id: "other" },
                () => gate.promise,
            );
            const edited = {
                ...own,
                title: "Read the revised contract",
                version: 3,
            };
            let current: Todo | undefined = edited;
            const preceding = changeAfterEdit
                ? changes.change(edited, (latest) => {
                      assert.deepEqual(latest, edited);
                      current = { ...edited, version: 4, completedAtMs: null };
                      return Promise.resolve(current);
                  })
                : blocked;
            const conflict = new Error("refused.todo_changed");
            const stale = changes.change(
                todo,
                (latest): Promise<Todo> | Promise<void> => {
                    if (latest.version !== current?.version) throw conflict;
                    current =
                        operation === "delete"
                            ? undefined
                            : {
                                  ...latest,
                                  completedAtMs: 2,
                                  version: latest.version + 1,
                              };
                    return current
                        ? Promise.resolve(current)
                        : Promise.resolve();
                },
            );
            const rejected = assert.rejects(stale, conflict);
            gate.resolve(undefined);
            await Promise.all([preceding, rejected]);
            assert.deepEqual(
                current,
                changeAfterEdit
                    ? { ...edited, version: 4, completedAtMs: null }
                    : edited,
            );
        }
    }
});
