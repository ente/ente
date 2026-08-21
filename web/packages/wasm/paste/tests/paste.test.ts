import { expect, test } from "vitest";
import { PasteClient } from "../pkg/ente_paste_wasm.js";

test("returns tagged paste errors", async () => {
    const client = new PasteClient("http://localhost");
    await expect(client.create("http://localhost", "")).rejects.toMatchObject({
        name: "empty_text",
    });
    await expect(client.open("http://localhost/ABC123")).rejects.toMatchObject({
        name: "missing_key",
    });
    client.free();
});
