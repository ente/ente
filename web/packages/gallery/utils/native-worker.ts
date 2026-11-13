import type { Electron, UtilityProcessType } from "ente-base/types/ipc";

export const createUtilityProcess = (
    electron: Electron,
    type: UtilityProcessType,
): Promise<MessagePort> => {
    // MessagePorts cannot travel through Electron's usual send/invoke IPC.
    const portEvent = `utilityProcessPort/${type}`;

    const port = new Promise<MessagePort>((resolve) => {
        const l = ({ source, data, ports }: MessageEvent) => {
            // Accept only messages relayed by this window's preload.
            if (source == window && data == portEvent) {
                window.removeEventListener("message", l);
                resolve(ports[0]!);
            }
        };
        window.addEventListener("message", l);
    });

    electron.triggerCreateUtilityProcess(type);

    return port;
};
