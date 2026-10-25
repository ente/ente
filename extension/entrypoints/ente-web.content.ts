// Runs only on the Ente Auth web app. When the user starts the "sign in via
// the browser" flow, this scraper reads the session the web app stores after a
// successful login (including passkey / email-verification logins that the
// extension cannot perform itself) and hands it to the background worker,
// which stashes it for the popup to unbox (the WASM crypto cannot run in a
// service worker).
//
// Nothing is read or sent unless the background worker has flagged that a web
// login is in progress.
import { browser } from "wxt/browser";
import { sendMessageToBackground } from "../utils/messaging";

const POLL_INTERVAL_MS = 1500;

export default defineContentScript({
    matches: ["https://auth.ente.com/*"],
    runAt: "document_idle",
    allFrames: false,
    main() {
        let timer: number | undefined;

        const stop = () => {
            if (timer !== undefined) window.clearInterval(timer);
            timer = undefined;
        };

        const readCredentials = () => {
            try {
                const userRaw = localStorage.getItem("user");
                const keyAttributesRaw = localStorage.getItem("keyAttributes");
                const masterRaw = sessionStorage.getItem("encryptionKey");
                if (!userRaw || !keyAttributesRaw || !masterRaw)
                    return undefined;

                const user = JSON.parse(userRaw) as {
                    id?: number;
                    email?: string;
                    token?: string;
                };
                if (!user?.token) return undefined;

                const masterKeyBox = JSON.parse(masterRaw) as {
                    encryptedData?: string;
                    nonce?: string;
                    key?: string;
                };
                if (
                    !masterKeyBox?.encryptedData ||
                    !masterKeyBox?.nonce ||
                    !masterKeyBox?.key
                )
                    return undefined;

                return {
                    token: user.token,
                    keyAttributes: JSON.parse(keyAttributesRaw) as unknown,
                    user: { id: user.id, email: user.email },
                    masterKeyBox: {
                        encryptedData: masterKeyBox.encryptedData,
                        nonce: masterKeyBox.nonce,
                        key: masterKeyBox.key,
                    },
                };
            } catch {
                // The web app may be mid-write; try again on the next tick.
                return undefined;
            }
        };

        const tryImport = async () => {
            const credentials = readCredentials();
            if (!credentials) return;
            const { received } = await sendMessageToBackground({
                type: "webLoginCredentials",
                credentials,
            });
            // Stop once the worker has accepted the credentials. If it was not
            // awaiting (e.g. the flow was cancelled), keep waiting instead of
            // dropping them.
            if (received) stop();
        };

        const startWatching = () => {
            if (timer !== undefined) return;
            void tryImport();
            timer = window.setInterval(
                () => void tryImport(),
                POLL_INTERVAL_MS,
            );
        };

        browser.runtime.onMessage.addListener((message: unknown) => {
            if ((message as { type?: string })?.type === "beginWebLoginWatch")
                startWatching();
        });

        // The tab may have just been opened by the background worker; ask once
        // whether a web login is pending.
        void sendMessageToBackground({ type: "isAwaitingWebLogin" })
            .then(({ awaiting }) => {
                if (awaiting) startWatching();
            })
            .catch(() => {
                // Worker asleep / not available; the explicit message will
                // start us if the flow begins later.
            });
    },
});
