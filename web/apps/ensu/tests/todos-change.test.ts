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
    changes.show([todo]);
    const completed = Promise.withResolvers<Todo>();
    const versions: number[] = [];
    const first = changes.change(todo, (latest) => {
        versions.push(latest.version);
        return completed.promise;
    });
    const second = changes.change(todo, (latest) => {
        versions.push(latest.version);
        assert.equal(latest.completedAtMs, 1);
        return Promise.resolve(latest);
    });
    await Promise.resolve();
    assert.deepEqual(versions, [1]);
    completed.resolve({ ...todo, completedAtMs: 1, version: 2 });
    await Promise.all([first, second]);
    assert.deepEqual(versions, [1, 2]);
});

void test("a failed To Do change leaves the next change queued", async () => {
    const changes = todoChanges();
    changes.show([todo]);
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
