import { abortable } from "../abortable.ts";

export class ModelOperationQueue {
    private tail: Promise<void> = Promise.resolve();

    async run<T>(
        operation: () => Promise<T>,
        signal?: AbortSignal,
    ): Promise<T> {
        signal?.throwIfAborted();
        const previous = this.tail;
        let release: () => void = () => undefined;
        const finished = new Promise<void>((resolve) => {
            release = resolve;
        });
        this.tail = previous.then(() => finished);
        try {
            if (signal) await abortable(previous, signal);
            else await previous;
            signal?.throwIfAborted();
            return await operation();
        } finally {
            release();
        }
    }
}
