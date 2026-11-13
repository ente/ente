export const wait = (ms: number): Promise<void> =>
    new Promise((resolve) => setTimeout(resolve, ms));

export const throttled = (
    underlying: () => Promise<void>,
    period: number,
): (() => void) => {
    let pending = 0;

    const f = () => {
        pending += 1;
        if (pending > 1) return;
        void underlying()
            .then(() => wait(period))
            .then(() => {
                const retrigger = pending > 1;
                pending = 0;
                if (retrigger) f();
            });
    };

    return f;
};

export const withTimeout = async <T>(
    promise: Promise<T>,
    ms: number,
): Promise<T> => {
    let timeoutId: ReturnType<typeof setTimeout>;
    const rejectOnTimeout = new Promise<T>((_, reject) => {
        timeoutId = setTimeout(
            () => reject(new Error("Operation timed out")),
            ms,
        );
    });
    const promiseAndCancelTimeout = async () => {
        const result = await promise;
        clearTimeout(timeoutId);
        return result;
    };
    return Promise.race([promiseAndCancelTimeout(), rejectOnTimeout]);
};

export class PromiseQueue<T> {
    private q: {
        task: () => Promise<T>;
        handlers: [
            (value: T | PromiseLike<T>) => void,
            (reason?: unknown) => void,
        ];
    }[] = [];

    async add(task: () => Promise<T>): Promise<T> {
        let handlers!: (typeof this.q)[number]["handlers"];
        const p = new Promise<T>((...args) => (handlers = args));
        this.q.push({ task, handlers });
        if (this.q.length == 1) this.next();
        return p;
    }

    private next() {
        const item = this.q[0];
        if (!item) return;
        const { task, handlers } = item;
        void task()
            .then(...handlers)
            .finally(() => {
                this.q.shift();
                this.next();
            });
    }
}
