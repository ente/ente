/// <reference types="chromecast-caf-receiver" />

import log from "ente-base/log";

export type Cast = typeof cast;

class CastReceiver {
    cast: Cast | undefined;
    loader: Promise<Cast> | undefined;
    // One way flag: stopping the Chromecast SDK makes the device reload our
    // tab, so there is no way to unset this.
    haveStarted = false;
    isChromecast: boolean | undefined;
    pairingCode: (() => string | undefined) | undefined;
    collectionID: (() => string | undefined) | undefined;
}

const castReceiver = new CastReceiver();

export const advertiseOnChromecast = (
    pairingCode: () => string | undefined,
    collectionID: () => string | undefined,
) => {
    castReceiver.pairingCode = pairingCode;
    castReceiver.collectionID = collectionID;

    if (castReceiver.haveStarted) return;

    void loadingChromecastSDKIfNeeded().then((cast) => advertiseCode(cast));
};

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
    if (castReceiver.haveStarted) return;

    castReceiver.haveStarted = true;

    const context = cast.framework.CastReceiverContext.getInstance();
    const namespace = "urn:x-cast:pair-request";

    const options = new cast.framework.CastReceiverOptions();
    options.skipPlayersLoad = true;
    options.disableIdleTimeout = true;

    interface ListenerProps {
        senderId: string;
        data: unknown;
    }

    const incomingMessageListener = ({ senderId, data }: ListenerProps) => {
        const pairedCollectionID = castReceiver.collectionID?.();

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

        if (collectionID && pairedCollectionID) {
            if (pairedCollectionID != collectionID) {
                log.info(`request for a new collection ${collectionID}`);
                context.stop();
            }
            return;
        }

        const code = castReceiver.pairingCode?.();
        if (!code) {
            if (pairedCollectionID) return;

            log.error("got pairing request when refreshing pairing codes");
            context.stop();
            return;
        }

        context.sendCustomMessage(namespace, senderId, { code });
    };

    context.addCustomMessageListener(namespace, incomingMessageListener);

    context.addEventListener(
        "senderdisconnected" as Parameters<typeof context.addEventListener>[0],
        () => context.stop(),
    );

    context.start(options);
};

// Some processing is too heavy for Chromecast hardware (as tested on a 2nd
// gen device; newer variants may do better).
export const isChromecast = () => {
    let isCast = castReceiver.isChromecast;
    if (isCast === undefined) {
        isCast = window.navigator.userAgent.includes("CrKey");
        castReceiver.isChromecast = isCast;
    }
    return isCast;
};
