import { evictCachedImage } from "./imageCache";

export class PreviewCache {
    private urls = new Map<string, string>();
    private users = new Map<string, number>();
    private pending = new Map<string, Promise<Blob | null>>();

    constructor(
        private load: (id: string) => Promise<Blob | null>,
        private onChange: (urls: Map<string, string>) => void,
    ) {}

    retain(photoIds: string[]): () => void {
        const ids = [...new Set(photoIds)];
        for (const id of ids) {
            this.users.set(id, (this.users.get(id) ?? 0) + 1);
            if (this.urls.has(id) || this.pending.has(id)) continue;
            const request = this.load(id);
            this.pending.set(id, request);
            void request
                .then((blob) => {
                    if (this.pending.get(id) !== request) return;
                    this.pending.delete(id);
                    if (blob) this.refresh(id, blob);
                })
                .catch((error: unknown) => {
                    if (this.pending.get(id) === request)
                        this.pending.delete(id);
                    console.error("Failed to load preview", error);
                });
        }
        return () => {
            const next = new Map(this.urls);
            for (const id of ids) {
                const count = (this.users.get(id) ?? 0) - 1;
                if (count > 0) {
                    this.users.set(id, count);
                    continue;
                }
                this.users.delete(id);
                this.pending.delete(id);
                const url = next.get(id);
                if (url) {
                    this.release(url);
                    next.delete(id);
                }
            }
            if (next.size !== this.urls.size) {
                this.urls = next;
                this.onChange(next);
            }
        };
    }

    refresh(id: string, blob: Blob): void {
        this.pending.delete(id);
        if (!this.users.has(id)) return;
        const previous = this.urls.get(id);
        if (previous) this.release(previous);
        this.urls = new Map(this.urls).set(id, URL.createObjectURL(blob));
        this.onChange(this.urls);
    }

    clear(): void {
        this.urls.forEach((url) => this.release(url));
        this.urls = new Map();
        this.users.clear();
        this.pending.clear();
        this.onChange(this.urls);
    }

    private release(url: string): void {
        URL.revokeObjectURL(url);
        evictCachedImage(url);
    }
}
