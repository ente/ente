import { isTauriRuntime } from "@/services/tauri-runtime";
import { secureStorageGet, secureStorageSet } from "../secure-storage";
import { ensureCryptoInit, enteWasm } from "../wasm";
import {
    hasRetiredLocalChatStore,
    promoteLocalChatKey,
    retiredBrowserChatKey,
} from "./compatibility";

const LOCAL_KEY = "ensu.chatKey.local";
const CURRENT_SECURE_KEY = "localChatKey.v2";

let _localKey: string | undefined;
let _initPromise: Promise<void> | undefined;

const localGet = (key: string) =>
    typeof localStorage === "undefined"
        ? undefined
        : (localStorage.getItem(key) ?? undefined);

export const initChatKeyStore = async () => {
    if (!isTauriRuntime()) return;
    if (_initPromise) return _initPromise;

    _initPromise = (async () => {
        const current = await secureStorageGet(CURRENT_SECURE_KEY);
        _localKey = await promoteLocalChatKey(
            current,
            CURRENT_SECURE_KEY,
            LOCAL_KEY,
        );
    })().catch((error: unknown) => {
        _initPromise = undefined;
        throw error;
    });
    return _initPromise;
};

export const cachedLocalChatKey = () => {
    if (isTauriRuntime()) return _localKey;
    const key = localGet(LOCAL_KEY) ?? retiredBrowserChatKey();
    if (key) localStorage.setItem(LOCAL_KEY, key);
    return key;
};

const persistLocalKey = async (key: string) => {
    if (isTauriRuntime()) {
        await secureStorageSet(CURRENT_SECURE_KEY, key);
        _localKey = key;
    } else {
        localStorage.setItem(LOCAL_KEY, key);
    }
};

const hasNativeChatStore = async () => {
    const { invoke } = await import("@tauri-apps/api/core");
    return invoke<boolean>("chat_db_has_existing_store");
};

export const getOrCreateLocalChatKey = async () => {
    await initChatKeyStore();
    const cached = cachedLocalChatKey();
    if (cached) return cached;
    if (
        hasRetiredLocalChatStore() ||
        (isTauriRuntime() && (await hasNativeChatStore()))
    ) {
        throw new Error("Existing chat data has no encryption key");
    }

    await ensureCryptoInit();
    const chatKey = await (await enteWasm()).crypto_generate_key();
    await persistLocalKey(chatKey);
    return chatKey;
};
