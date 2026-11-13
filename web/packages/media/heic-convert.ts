import { ComlinkWorker } from "ente-base/worker/comlink-worker";
import type { HEICConvertWorker } from "./heic-convert.worker";

// The conversion runs in a web worker, using a Wasm HEIC conversion package.
export const heicToJPEG = async (heicBlob: Blob) =>
    worker().then((w) => w.heicToJPEG(heicBlob));

let _comlinkWorker: ComlinkWorker<typeof HEICConvertWorker> | undefined;

const worker = async () => (_comlinkWorker ??= createComlinkWorker()).remote;

const createComlinkWorker = () =>
    new ComlinkWorker<typeof HEICConvertWorker>(
        "heic-convert-worker",
        new Worker(new URL("heic-convert.worker.ts", import.meta.url)),
    );
