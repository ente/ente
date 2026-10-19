interface IdleTimers {
    schedule: (callback: () => void, delayMs: number) => number;
    cancel: (handle: number) => void;
}

export class NotesIndexingIdleScheduler {
    private timer?: number;
    private waiting = false;
    private revision = 0;

    constructor(
        private resume: () => void,
        private isChatBusy: () => boolean,
        private timers: IdleTimers,
        private quietPeriodMs = 30_000,
    ) {}

    defer() {
        this.waiting = true;
        this.schedule();
    }

    activity() {
        if (this.waiting) this.schedule();
    }

    resumeNow() {
        this.cancel();
        this.resume();
    }

    cancel() {
        this.revision += 1;
        this.waiting = false;
        if (this.timer !== undefined) this.timers.cancel(this.timer);
        this.timer = undefined;
    }

    private schedule() {
        if (this.timer !== undefined) this.timers.cancel(this.timer);
        const revision = ++this.revision;
        this.timer = this.timers.schedule(() => {
            if (!this.waiting || revision !== this.revision) return;
            this.timer = undefined;
            if (this.isChatBusy()) {
                this.schedule();
                return;
            }
            this.waiting = false;
            this.resume();
        }, this.quietPeriodMs);
    }
}
