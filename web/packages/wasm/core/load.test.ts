import { afterEach, expect, test, vi } from "vitest";

afterEach(() => {
    vi.resetModules();
    vi.restoreAllMocks();
});

test("loadEnteWasm shares the same import promise", async () => {
    const wasmModule = { crypto_init: vi.fn() };
    const importFactory = vi.fn(() => Promise.resolve(wasmModule));
    vi.doMock("ente-core-wasm", importFactory);

    const { loadEnteWasm } = await import("./load");

    const first = loadEnteWasm();
    const second = loadEnteWasm();

    expect(first).toBe(second);
    await expect(first).resolves.toMatchObject({
        crypto_init: wasmModule.crypto_init,
    });
    await expect(second).resolves.toMatchObject({
        crypto_init: wasmModule.crypto_init,
    });
    expect(importFactory).toHaveBeenCalledTimes(1);
});

test("loadCryptoReadyEnteWasm initializes crypto once", async () => {
    const crypto_init = vi.fn();
    const wasmModule = { crypto_init };
    const importFactory = vi.fn(() => Promise.resolve(wasmModule));
    vi.doMock("ente-core-wasm", importFactory);

    const { loadCryptoReadyEnteWasm } = await import("./load");

    const first = loadCryptoReadyEnteWasm();
    const second = loadCryptoReadyEnteWasm();

    expect(first).toBe(second);

    const [firstModule, secondModule] = await Promise.all([first, second]);
    expect(firstModule.crypto_init).toBe(crypto_init);
    expect(secondModule.crypto_init).toBe(crypto_init);
    expect(importFactory).toHaveBeenCalledTimes(1);
    expect(crypto_init).toHaveBeenCalledTimes(1);
});

test("loadCryptoReadyEnteWasm retries after crypto init failure", async () => {
    let attempts = 0;
    const crypto_init = vi.fn(() => {
        attempts += 1;
        if (attempts === 1) {
            throw new Error("init failed");
        }
    });
    const wasmModule = { crypto_init };
    vi.doMock("ente-core-wasm", () => wasmModule);

    const { loadCryptoReadyEnteWasm } = await import("./load");

    await expect(loadCryptoReadyEnteWasm()).rejects.toThrow("init failed");
    await expect(loadCryptoReadyEnteWasm()).resolves.toMatchObject({
        crypto_init,
    });
    expect(crypto_init).toHaveBeenCalledTimes(2);
});

test("loadEnteWasm retries after a failed load attempt", async () => {
    const wasmModule = { crypto_init: vi.fn() };
    let attempts = 0;
    vi.doMock("ente-core-wasm", () => {
        attempts += 1;
        if (attempts === 1) {
            throw new Error("import failed");
        }
        return Promise.resolve(wasmModule);
    });

    const { loadEnteWasm } = await import("./load");

    await expect(loadEnteWasm()).rejects.toBeTruthy();
    await expect(loadEnteWasm()).resolves.toMatchObject({
        crypto_init: wasmModule.crypto_init,
    });
    expect(attempts).toBe(2);
});
