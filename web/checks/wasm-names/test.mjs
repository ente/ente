import { ESLint } from "eslint";
import assert from "node:assert/strict";
import { resolve } from "node:path";
import test from "node:test";

const eslint = new ESLint({
    cwd: resolve(import.meta.dirname, "../.."),
    overrideConfigFile: resolve(import.meta.dirname, "eslint.config.mjs"),
    allowInlineConfig: false,
});
const filePath = "packages/wasm/example/pkg/ente_example_wasm.d.ts";

test("generated APIs allow Rust parameters and disposal hooks", async () => {
    const [result] = await eslint.lintText(
        `/* eslint-disable */
        export interface ResultData { publicKey: string; }
        export class CryptoKey {
            private constructor();
            free(): void;
            [Symbol.dispose](): void;
            computeValue(rust_parameter: string): ResultData;
            readonly publicKey: string;
            get currentValue(): number;
        }
        export function deriveKey(key_bytes: Uint8Array): CryptoKey;`,
        { filePath },
    );
    assert.deepEqual(result.messages, []);
});

test("generated API naming cannot be suppressed inline", async () => {
    const [result] = await eslint.lintText(
        `/* eslint-disable */
        export interface result_data { public_key: string; }
        export class crypto_key {
            compute_value(): void;
            readonly secret_key: string;
            get current_value(): number;
        }
        // eslint-disable-next-line @typescript-eslint/naming-convention
        export function derive_key(): void;`,
        { filePath },
    );
    assert.equal(result.messages.length, 7);
    assert.ok(
        result.messages.every(
            ({ ruleId, severity }) =>
                ruleId === "@typescript-eslint/naming-convention" &&
                severity === 2,
        ),
    );
});

test("low-level WASM declarations are excluded", async () => {
    assert.ok(
        await eslint.isPathIgnored(
            "packages/wasm/example/pkg/ente_example_wasm_bg.wasm.d.ts",
        ),
    );
});
