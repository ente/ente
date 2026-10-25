import { browser } from "wxt/browser";
import { codeForHost, hasMatchForHost } from "../utils/cached-codes";
import {
    restrictSessionStorageToTrustedContexts,
    setSession,
} from "../utils/ente/storage";
import type { ExtensionRequest } from "../utils/messaging";
import { SESSION } from "../utils/session-keys";

// The Ente Auth web app, used for the "sign in via the browser" hand-off.
const WEB_LOGIN_URL = "https://auth.ente.com";
const WEB_LOGIN_ORIGINS = ["https://auth.ente.com/*"];

// Set while a browser-based login is pending, so the content script only sends
// credentials when the user actually asked for this flow.
const AWAITING_KEY = "webLoginAwaiting";

const isAwaitingWebLogin = async (): Promise<boolean> =>
    !!(await browser.storage.session.get(AWAITING_KEY))[AWAITING_KEY];

const setAwaitingWebLogin = (awaiting: boolean) =>
    awaiting
        ? browser.storage.session.set({ [AWAITING_KEY]: true })
        : browser.storage.session.remove(AWAITING_KEY);

// Bring an existing Ente web tab to the front and tell it to start watching,
// or open a fresh one.
const openWebLogin = async () => {
    const [existing] = await browser.tabs.query({ url: WEB_LOGIN_ORIGINS });
    if (existing?.id !== undefined) {
        await browser.tabs.update(existing.id, { active: true });
        if (existing.windowId !== undefined)
            await browser.windows.update(existing.windowId, { focused: true });
        try {
            await browser.tabs.sendMessage(existing.id, {
                type: "beginWebLoginWatch",
            });
        } catch {
            // The content script may not be injected yet; it will ask on load.
        }
        return;
    }
    await browser.tabs.create({ url: WEB_LOGIN_URL });
};

export default defineBackground({
    main() {
        // Keep the per-session decrypted vault out of content scripts.
        void restrictSessionStorageToTrustedContexts();

        browser.runtime.onMessage.addListener(
            (
                message: unknown,
                _sender,
                sendResponse: (response: unknown) => void,
            ) => {
                const request = message as ExtensionRequest;
                switch (request?.type) {
                    case "hasMatchForHost":
                        void hasMatchForHost(request.host)
                            .then((match) => sendResponse({ match }))
                            .catch(() => sendResponse({ match: false }));
                        return true;
                    case "requestCodeForHost":
                        void codeForHost(request.host)
                            .then((code) => sendResponse({ code }))
                            .catch(() => sendResponse({ code: null }));
                        return true;
                    case "isAwaitingWebLogin":
                        void isAwaitingWebLogin()
                            .then((awaiting) => sendResponse({ awaiting }))
                            .catch(() => sendResponse({ awaiting: false }));
                        return true;
                    case "startWebLogin":
                        void (async () => {
                            await setAwaitingWebLogin(true);
                            await openWebLogin();
                            sendResponse({ started: true });
                        })().catch(() => sendResponse({ started: false }));
                        return true;
                    case "webLoginCredentials":
                        void (async () => {
                            if (!(await isAwaitingWebLogin())) {
                                sendResponse({ received: false });
                                return;
                            }
                            // Stash the raw credentials. The WASM crypto
                            // stack cannot be loaded here (dynamic `import()`
                            // is disabled in service workers), so the popup
                            // picks these up and unboxes them.
                            await setSession(
                                SESSION.pendingWebLogin,
                                request.credentials,
                            );
                            await setAwaitingWebLogin(false);
                            sendResponse({ received: true });
                        })().catch(() => sendResponse({ received: false }));
                        return true;
                    default:
                        return false;
                }
            },
        );
    },
});
