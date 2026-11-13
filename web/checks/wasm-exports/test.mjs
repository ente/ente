import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import ts from "typescript";
import { rustExports, unusedExports } from "./exports.mjs";

test("production references cross lazy loaders, aliases, destructuring and workers", () => {
    const directory = mkdtempSync(join(tmpdir(), "wasm-exports-"));
    const file = (name, contents) => {
        const path = join(directory, name);
        writeFileSync(path, contents);
        return path;
    };
    try {
        const bindings = file(
            "raw.d.ts",
            `
            export function used(): void;
            export function destructured(): void;
            export function aliased(): void;
            export function indexed(): void;
            export function workerOnly(): void;
            export function orphan(): void;
            export function testOnly(): void;
            export function typeOnly(): void;
            export function wrapperOnly(): void;
            export function start(): void;
            export class Handle {
                constructor();
                free(): void;
                [Symbol.dispose](): void;
                readonly key: string;
                run(): void;
                orphan(): void;
                testOnly(): void;
                constraintOnly(): void;
            }
        `,
        );
        const wrapper = file(
            "wrapper.ts",
            `
            const wasm = () => import("./raw");
            export const run = async () => {
                (await wasm()).used();
                const { destructured: read } = await wasm();
                read();
                (await wasm())["indexed"]();
            };
            export const unusedForwarder = async () => (await wasm()).wrapperOnly();
        `,
        );
        const entry = file(
            "entry.ts",
            `
            import { run as execute } from "./wrapper";
            import { aliased as action } from "./raw";
            execute();
            action();
            import { Handle } from "./raw";
            const handle = new Handle();
            handle.run();
            console.log(handle.key);
            const ignore = <T extends { constraintOnly(): void }>(handle: T) => {};
            ignore(handle);
            const unrelated = { orphan() {} };
            unrelated.orphan();
            type Signature = typeof import("./raw").typeOnly;
            new Worker(new URL("./worker.ts", import.meta.url));
        `,
        );
        file("worker.ts", `import { workerOnly } from "./raw"; workerOnly();`);
        file("unused.ts", `import { orphan } from "./raw"; orphan();`);
        file(
            "binding.test.ts",
            `import { testOnly, Handle } from "./raw"; testOnly(); new Handle().testOnly();`,
        );
        const projects = [
            {
                entryFiles: [entry],
                options: {
                    module: ts.ModuleKind.ESNext,
                    moduleResolution: ts.ModuleResolutionKind.Bundler,
                },
            },
        ];
        const check = () =>
            unusedExports([bindings, wrapper], projects)
                .map(({ name }) => name)
                .sort();
        assert.deepEqual(check(), [
            "Handle.constraintOnly",
            "Handle.orphan",
            "Handle.testOnly",
            "orphan",
            "testOnly",
            "typeOnly",
            "unusedForwarder",
        ]);

        file(
            "wrapper.ts",
            `export const run = async () => {
            const wasm = await import("./raw");
            wasm.used(); wasm.destructured(); wasm.indexed();
        };`,
        );
        assert.deepEqual(check(), [
            "Handle.constraintOnly",
            "Handle.orphan",
            "Handle.testOnly",
            "orphan",
            "testOnly",
            "typeOnly",
            "wrapperOnly",
        ]);
    } finally {
        rmSync(directory, { recursive: true, force: true });
    }
});

test("module arguments and props reference only the receiving contract", () => {
    const directory = mkdtempSync(join(tmpdir(), "wasm-module-exports-"));
    const bindings = join(directory, "bindings.ts");
    const entry = join(directory, "entry.tsx");
    try {
        writeFileSync(
            bindings,
            `
            export const getInfo = (_session: number) => {};
            export const publicKey = () => "key";
            export const unused = () => {};
        `,
        );
        const consumers = `
            import * as legacy from "./bindings";
            function Panel<Session>({ session, legacy }: {
                session: Session;
                legacy: { getInfo(session: Session): void };
            }) {
                legacy.getInfo(session);
                return null;
            }
            function verify(api: { publicKey(): string }) {
                return api.publicKey();
            }
            verify(legacy);
        `;
        const check = () =>
            unusedExports(
                [bindings],
                [
                    {
                        entryFiles: [entry],
                        options: {
                            jsx: ts.JsxEmit.Preserve,
                            module: ts.ModuleKind.ESNext,
                            moduleResolution: ts.ModuleResolutionKind.Bundler,
                        },
                    },
                ],
            ).map(({ name }) => name);

        writeFileSync(
            entry,
            consumers + "<Panel session={42} legacy={legacy} />;",
        );
        assert.deepEqual(check(), ["unused"]);

        writeFileSync(entry, consumers);
        assert.deepEqual(check(), ["getInfo", "unused"]);
    } finally {
        rmSync(directory, { recursive: true, force: true });
    }
});

test("copies of a Rust export need one caller across artifacts", () => {
    const directory = mkdtempSync(join(tmpdir(), "wasm-export-origins-"));
    const file = (name, contents) => {
        const path = join(directory, name);
        writeFileSync(path, contents);
        return path;
    };
    try {
        const shared = file(
            "shared.rs",
            `
#[wasm_bindgen(js_name = sharedOperation)]
pub fn shared_operation() {}

pub fn internal_helper() {}

#[wasm_bindgen]
impl Session {
    #[wasm_bindgen(js_name = updateAuthToken)]
    pub fn update_auth_token(&self, token: String) {}
}
`,
        );
        const appSource = (app) =>
            file(
                `${app}.rs`,
                `
#[wasm_bindgen(js_name = localOperation)]
pub fn local_operation() {}
`,
            );
        const leftSource = appSource("left");
        const rightSource = appSource("right");
        const declarations = `
            export function sharedOperation(): void;
            export function localOperation(): void;
            export class Session {
                private constructor();
                free(): void;
                updateAuthToken(token: string): void;
            }
        `;
        const left = file("left.d.ts", declarations);
        const right = file("right.d.ts", declarations);
        const origins = new Map([
            [left, rustExports([shared, leftSource])],
            [right, rustExports([shared, rightSource])],
        ]);
        const entry = file(
            "entry.ts",
            `
            import { sharedOperation, localOperation } from "./left";
            sharedOperation();
            localOperation();
            import type { Session } from "./left";
            const cache = <T extends { updateAuthToken(token: string): void }>(open: () => Promise<T>) => {
                void open().then(session => session.updateAuthToken("token"));
            };
            declare const open: () => Promise<Session>;
            cache(open);
        `,
        );
        file(
            "right.test.ts",
            `import { localOperation } from "./right"; localOperation();`,
        );
        const check = () =>
            unusedExports(
                [left, right],
                [
                    {
                        entryFiles: [entry],
                        options: {
                            module: ts.ModuleKind.ESNext,
                            moduleResolution: ts.ModuleResolutionKind.Bundler,
                        },
                    },
                ],
                origins,
            ).map(({ file, name }) => ({ file, name }));

        assert.deepEqual(check(), [
            { file: rightSource, name: "localOperation" },
        ]);

        file(
            "entry.ts",
            `import { localOperation } from "./left"; localOperation();`,
        );
        file(
            "shared.test.ts",
            `import { sharedOperation } from "./right"; sharedOperation();`,
        );
        assert.deepEqual(check(), [
            { file: shared, name: "sharedOperation" },
            { file: shared, name: "Session.updateAuthToken" },
            { file: rightSource, name: "localOperation" },
        ]);

        file("right.d.ts", declarations + "export function unmapped(): void;");
        assert.throws(check, /cannot locate Rust export unmapped/);
    } finally {
        rmSync(directory, { recursive: true, force: true });
    }
});
