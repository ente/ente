/// <reference types="chromecast-caf-receiver" />

import log from "ente-base/log";

export type Cast = typeof cast;

/**
 * A holder for the "cast" global object exposed by the Chromecast SDK,
 * alongwith auxiliary state we need around it.
 */
class CastReceiver {
    /**
     * A reference to the `cast` global object that the Chromecast Web Receiver
     * SDK attaches to the window.
     *
     * https://developers.google.com/cast/docs/web_receiver/basic
     */
    cast: Cast | undefined;
    /**
     * A promise that allows us to ensure multiple requests to load are funneled
     * through the same reified load.
     */
    loader: Promise<Cast> | undefined;
    /**
     * True if we have already attached listeners (i.e. if we have "started" the
     * Chromecast SDK).
     *
     * Note that "stopping" the Chromecast SDK causes the Chromecast device to
     * reload our tab, so this is a one way flag. The stop is something that'll
     * only get triggered when we're actually running on a Chromecast since it
     * always happens in response to a message handler.
     */
    haveStarted = false;
    /**
     * Cached result of the isChromecast test.
     */
    isChromecast: boolean | undefined;
    /**
     * A callback to invoke to get the pairing code when we get a new incoming
     * pairing request.
     */
    pairingCode: (() => string | undefined) | undefined;
    /**
     * A callback to invoke to get the ID of the collection that is currently
     * being shown (if any).
     */
    collectionID: (() => string | undefined) | undefined;
}

/** Singleton instance of {@link CastReceiver}. */
const castReceiver = new CastReceiver();

/**
 * Listen for incoming messages on the given {@link cast} receiver, replying to
 * each of them with a pairing code obtained using the given {@link pairingCode}
 * callback. Phase 2 of the pairing protocol.
 *
 * Calling this function multiple times is fine. The first time around, the
 * Chromecast SDK will be loaded and will start listening. Subsequently, each
 * time this is call, we'll update the callbacks, but otherwise just return
 * immediately (letting the already attached listeners do their thing).
 *
 * @param pairingCode A callback to invoke to get the pairing code when we get a
 * new incoming pairing request.
 *
 * @param collectionID A callback to invoke to get the ID of the collection that
 * is currently being shown (if any).
 *
 * See: [Note: Pairing protocol].
 */
export const advertiseOnChromecast = (
    pairingCode: () => string | undefined,
    collectionID: () => string | undefined,
) => {
    // Always update the callbacks.
    castReceiver.pairingCode = pairingCode;
    castReceiver.collectionID = collectionID;

    // No-op if we're already running.
    if (castReceiver.haveStarted) return;

    void loadingChromecastSDKIfNeeded().then((cast) => advertiseCode(cast));
};

/**
 * Load the Chromecast Web Receiver SDK and return a reference to the `cast`
 * global object that the SDK attaches to the window.
 *
 * Calling this function multiple times is fine, once the Chromecast SDK is
 * loaded it'll thereafter return the reference to the same object always.
 */
const loadingChromecastSDKIfNeeded = async (): Promise<Cast> => {
    if (castReceiver.cast) return castReceiver.cast;
    if (castReceiver.loader) return await castReceiver.loader;

    castReceiver.loader = new Promise((resolve) => {
        const script = document.createElement("script");
        script.src =
            "https://www.gstatic.com/cast/sdk/libs/caf_receiver/v3/cast_receiver_framework.js";
        script.addEventListener("load", () => {
            castReceiver.cast = cast;
            resolve(cast);
        });
        document.body.appendChild(script);
    });

    return await castReceiver.loader;
};

const advertiseCode = (cast: Cast) => {
    if (castReceiver.haveStarted) {
        // Multiple attempts raced to completion, ignore all but the first.
        return;
    }

    castReceiver.haveStarted = true;

    // Prepare the Chromecast "context".
    const context = cast.framework.CastReceiverContext.getInstance();
    const namespace = "urn:x-cast:pair-request";

    const options = new cast.framework.CastReceiverOptions();
    // We don't use the media features of the Cast SDK.
    options.skipPlayersLoad = true;
    // Do not stop the casting if the receiver is unreachable. A user should be
    // able to start a cast on their phone and then put it away, leaving the
    // cast running on their big screen.
    options.disableIdleTimeout = true;

    interface ListenerProps {
        senderId: string;
        data: unknown;
    }

    // Reply with the code that we have if anyone asks over Chromecast.
    const incomingMessageListener = ({ senderId, data }: ListenerProps) => {
        // The collection ID with is currently paired (if any).
        const pairedCollectionID = castReceiver.collectionID?.();

        // The collection ID in the request (if any).

        let collectionID: string | null = null;
        if (
            typeof data == "object" &&
            data !== null &&
            "collectionID" in data &&
            (typeof data.collectionID == "string" ||
                typeof data.collectionID == "number")
        ) {
            collectionID = data.collectionID.toString();
        }

        // If the request does not have a collectionID (or if we're not showing
        // anything currently), forego this check.

        if (collectionID && pairedCollectionID) {
            // If we get another connection request for a _different_ collection
            // ID, stop the app to allow the second device to reconnect using a
            // freshly generated pairing code.
            if (pairedCollectionID != collectionID) {
                log.info(`request for a new collection ${collectionID}`);
                context.stop();
            } else {
                // Duplicate request for same collection that we're already
                // showing. Ignore.
            }
            return;
        }

        const code = castReceiver.pairingCode?.();
        if (!code) {
            // No code, but if we're already showing a collection, then ignore.
            if (pairedCollectionID) return;

            // Our caller waits until it has a pairing code before it calls
            // `advertiseCode`, but there is still an edge case where we can
            // find ourselves without a pairing code:
            //
            // 1. The current pairing code expires. We start the process to get
            //    a new one.
            //
            // 2. But before that happens, someone connects.
            //
            // The window where this can happen is short, so if we do find
            // ourselves in this scenario, just shutdown.
            log.error("got pairing request when refreshing pairing codes");
            context.stop();
            return;
        }

        context.sendCustomMessage(namespace, senderId, { code });
    };

    context.addCustomMessageListener(namespace, incomingMessageListener);

    // Close the (chromecast) tab if the sender disconnects.
    //
    // Chromecast does a "shutdown" of our cast app when we call `context.stop`.
    // This translates into it closing the tab where it is showing our app.
    context.addEventListener(
        "senderdisconnected" as Parameters<typeof context.addEventListener>[0],
        () => context.stop(),
    );

    // Start listening for Chromecast connections.
    context.start(options);
};

/**
 * Return true if we're running on a Chromecast device.
 *
 * This allows changing our app's behaviour when we're running on Chromecast.
 * Such checks are needed because during our testing we found that in practice,
 * some processing is too heavy for Chromecast hardware (we tested with a 2nd
 * gen device, this might not be true for newer variants).
 *
 * This variable is lazily updated when we enter {@link renderableImageURLs}. It
 * is kept at the top level to avoid passing it around.
 */
export const isChromecast = () => {
    let isCast = castReceiver.isChromecast;
    if (isCast === undefined) {
        isCast = window.navigator.userAgent.includes("CrKey");
        castReceiver.isChromecast = isCast;
    }
    return isCast;
};
