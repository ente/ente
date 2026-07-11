import { expect, test } from "vitest";
import { contacts_open_ctx } from "../pkg/ente_wasm.js";

test("contacts errors cross as an Error carrying a tagged shape", async () => {
    try {
        await contacts_open_ctx(42);
        expect.unreachable();
    } catch (e) {
        expect(e).toBeInstanceOf(Error);
        expect(e).toMatchObject({ kind: "serde" });
        expect((e as Error).message).not.toBe("");
        expect(String(e)).toContain((e as Error).message);
    }
});
