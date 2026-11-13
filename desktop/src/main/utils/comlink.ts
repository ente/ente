import type { Endpoint } from "comlink";
import type { MessagePortMain } from "electron";

// Adapted from Comlink's nodeEndpoint for Electron's MessagePortMain:
// https://github.com/GoogleChromeLabs/comlink/blob/main/src/node-adapter.ts
export const messagePortMainEndpoint = (mp: MessagePortMain): Endpoint => {
    type NL = EventListenerOrEventListenerObject;
    type EL = (data: Electron.MessageEvent) => void;
    const listeners = new WeakMap<NL, EL>();
    return {
        postMessage: (message, transfer) => {
            mp.postMessage(message, (transfer ?? []) as MessagePortMain[]);
        },
        addEventListener: (_, eh) => {
            const l: EL = (data) =>
                "handleEvent" in eh
                    ? eh.handleEvent({ data } as MessageEvent)
                    : eh(data as unknown as MessageEvent);
            mp.on("message", (data) => {
                l(data);
            });
            listeners.set(eh, l);
        },
        removeEventListener: (_, eh) => {
            const l = listeners.get(eh);
            if (!l) return;
            mp.off("message", l);
            listeners.delete(eh);
        },
        start: mp.start.bind(mp),
    };
};
