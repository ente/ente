import { wrap } from "comlink";
import { inWorker } from "../env";
import type { WorkerBridge } from "./comlink-worker";

// Calls are relayed asynchronously to workerBridge exposed by the main thread.
export const workerBridge = inWorker()
    ? wrap<WorkerBridge>(globalThis)
    : undefined;
