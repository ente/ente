export const deriveKeyInsufficientMemoryErrorMessage =
    "Failed to derive key (insufficient memory)";

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

const normalizeDerivedKeyError = (error: unknown): Error => {
    const code =
        typeof error === "object" && error && "code" in error
            ? String(error.code)
            : undefined;
    if (error instanceof Error) {
        if (
            code === "insufficient_memory" ||
            error.message.includes("insufficient memory") ||
            error.message.includes("KeyDerivationFailed") ||
            error.message.includes("key_derivation_failed")
        ) {
            return new Error(deriveKeyInsufficientMemoryErrorMessage);
        }
        return error;
    }
    return new Error(deriveKeyInsufficientMemoryErrorMessage);
};

// wasm-bindgen errors are not Errors and cannot cross Comlink's structured clone.
const toPlainError = (error: unknown): Error => {
    if (error instanceof Error) return error;
    const message =
        typeof error === "object" && error && "message" in error
            ? error.message
            : error;
    return new Error(String(message));
};

export const deriveKey = async (
    password: string,
    saltB64: string,
    opsLimit: number,
    memLimit: number,
) => {
    try {
        const wasm = await import("ente-core-wasm");
        return wasm.auth_derive_kek(password, saltB64, memLimit, opsLimit);
    } catch (error) {
        throw toPlainError(error);
    }
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
    try {
        return normalizeDerivedKey(wasm.auth_generate_sensitive_kek(password));
    } catch (error) {
        throw normalizeDerivedKeyError(error);
    }
};

export const deriveInteractiveKey = async (
    password: string,
): Promise<DerivedKey> => {
    const wasm = await import("ente-core-wasm");
    try {
        return normalizeDerivedKey(
            wasm.auth_generate_interactive_kek(password),
        );
    } catch (error) {
        throw normalizeDerivedKeyError(error);
    }
};
