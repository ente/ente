// Typed messages between the content script and the background worker.
import { browser } from "wxt/browser";

export interface CodeForHost {
    otp: string;
    nextOTP: string;
    validFor: number;
    issuer: string;
    account?: string;
}

export type ExtensionRequest =
    | { type: "hasMatchForHost"; host: string }
    | { type: "requestCodeForHost"; host: string }
    | { type: "isAwaitingWebLogin" }
    | { type: "startWebLogin" }
    | { type: "webLoginCredentials"; credentials: WebLoginCredentials };

// Raw credentials scraped from a logged-in `auth.ente.com` tab. The master key
// is boxed with a session key stored right next to it (Ente's sessionStorage
// format). Unboxing needs the WASM crypto stack, which uses dynamic `import()`
// and therefore cannot run in the background service worker; the popup, which
// already loads that stack, does the unboxing instead.
export interface WebLoginCredentials {
    token: string;
    keyAttributes: unknown;
    user?: { id?: number; email?: string };
    masterKeyBox: { encryptedData: string; nonce: string; key: string };
}

export interface ExtensionResponseMap {
    hasMatchForHost: { match: boolean };
    requestCodeForHost: { code: CodeForHost | null };
    isAwaitingWebLogin: { awaiting: boolean };
    startWebLogin: { started: boolean };
    webLoginCredentials: { received: boolean };
}

export const sendMessageToBackground = async <
    T extends ExtensionRequest["type"],
>(
    message: Extract<ExtensionRequest, { type: T }>,
): Promise<ExtensionResponseMap[T]> =>
    (await browser.runtime.sendMessage(message)) as ExtensionResponseMap[T];
