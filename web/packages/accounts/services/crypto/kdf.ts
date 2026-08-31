export interface DerivedKey {
    key: string;
    salt: string;
    opsLimit: number;
    memLimit: number;
}

interface WasmDerivedKey {
    key: string;
    salt: string;
    ops_limit: number;
    mem_limit: number;
}

export const deriveKey = async (
    password: string,
    saltB64: string,
    opsLimit: number,
    memLimit: number,
) => {
    const wasm = await import("ente-core-wasm");
    return wasm.auth_derive_kek(password, saltB64, memLimit, opsLimit);
};

const normalizeDerivedKey = (result: WasmDerivedKey): DerivedKey => ({
    key: result.key,
    salt: result.salt,
    opsLimit: result.ops_limit,
    memLimit: result.mem_limit,
});

export const deriveSensitiveKey = async (
    password: string,
): Promise<DerivedKey> => {
    const wasm = await import("ente-core-wasm");
    return normalizeDerivedKey(wasm.auth_generate_sensitive_kek(password));
};

export const deriveInteractiveKey = async (
    password: string,
): Promise<DerivedKey> => {
    const wasm = await import("ente-core-wasm");
    return normalizeDerivedKey(wasm.auth_generate_interactive_kek(password));
};
