import assert from "node:assert/strict";
import test from "node:test";
import { watchTodos } from "../src/services/todos.ts";

const tick = () => new Promise<void>((resolve) => setImmediate(resolve));

void test("To Do watchers retain current reads across registration, refresh and disposal", async () => {
    const registered = Promise.withResolvers<() => void>();
    const reads: ReturnType<typeof Promise.withResolvers<string>>[] = [];
    const values: string[] = [];
    const errors: unknown[] = [];
    let changed: () => void = () => undefined;
    let stopped = 0;
    const watcher = watchTodos(
        () => {
            const read = Promise.withResolvers<string>();
            reads.push(read);
            return read.promise;
        },
        (value) => values.push(value),
        (error) => errors.push(error),
        (onChange) => {
            changed = onChange;
            return registered.promise;
        },
    );
    const readAt = (index: number) => {
        const read = reads[index];
        assert.ok(read);
        return read;
    };
    assert.equal(reads.length, 1);
    registered.resolve(() => stopped++);
    await tick();
    assert.equal(reads.length, 2);
    readAt(1).resolve("registered");
    await tick();
    readAt(0).resolve("before subscription");
    await tick();
    assert.deepEqual(values, ["registered"]);

    watcher.refresh();
    changed();
    readAt(3).resolve("changed");
    readAt(2).reject(new Error("superseded"));
    await tick();
    assert.deepEqual(values, ["registered", "changed"]);
    assert.deepEqual([...errors], []);
    watcher.refresh();
    const failure = new Error("current read failed");
    readAt(4).reject(failure);
    await tick();
    assert.deepEqual([...errors], [failure]);

    watcher.refresh();
    watcher.dispose();
    readAt(5).resolve("disposed");
    changed();
    watcher.refresh();
    watcher.dispose();
    await tick();
    assert.deepEqual(values, ["registered", "changed"]);
    assert.equal(reads.length, 6);
    assert.equal(stopped, 1);

    const lateRegistration = Promise.withResolvers<() => void>();
    const lateRead = Promise.withResolvers<string>();
    let lateQueries = 0;
    const lateWatcher = watchTodos(
        () => {
            lateQueries++;
            return lateRead.promise;
        },
        (value) => values.push(value),
        (error) => errors.push(error),
        () => lateRegistration.promise,
    );
    lateWatcher.dispose();
    lateRegistration.resolve(() => stopped++);
    lateRead.reject(new Error("disposed read"));
    await tick();
    lateWatcher.dispose();
    assert.equal(lateQueries, 1);
    assert.equal(stopped, 2);
    assert.deepEqual([...errors], [failure]);
});
