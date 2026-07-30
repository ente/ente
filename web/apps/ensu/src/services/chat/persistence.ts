import log from "ente-base/log";
import { openChatStoreWithCompatibility } from "./compatibility";

let _initPromise: Promise<void> | undefined;

export const initializeChatStorePersistence = async (chatKey: string) => {
    if (_initPromise) return _initPromise;
    const promise = openChatStoreWithCompatibility(chatKey).catch(
        (error: unknown) => {
            if (_initPromise === promise) _initPromise = undefined;
            log.error("Failed to initialize chat persistence", error);
            throw error;
        },
    );
    _initPromise = promise;
    return promise;
};
