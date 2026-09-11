// Sender and receiver @types conflict, so declare only the sender APIs used here.

declare global {
    interface Window {
        cast: typeof cast;
        chrome?: unknown;
        __onGCastApiAvailable(available: boolean, reason?: string): void;
    }
}

export declare namespace chrome.cast {
    export enum AutoJoinPolicy {
        ORIGIN_SCOPED = "origin_scoped",
    }
}

export declare namespace cast.framework {
    interface CastOptions {
        autoJoinPolicy: chrome.cast.AutoJoinPolicy;
        receiverApplicationId?: string | undefined;
    }

    class CastContext {
        static getInstance(): CastContext;
        setOptions(options: CastOptions): void;
        requestSession(): Promise<unknown>;
        getCurrentSession(): CastSession | null;
    }

    class CastSession {
        sendMessage(namespace: string, data: unknown): Promise<unknown>;
        addMessageListener(
            namespace: string,
            listener: (namespace: string, message: string) => void,
        ): void;
    }
}
