// Mimics the localForage interface, but deliberately keeps data only in
// memory, never persisting it, so that each iframe embed stays isolated from
// other embeds.
class InMemoryStorage {
    private storage = new Map<string, unknown>();

    getItem(key: string): unknown {
        const value = this.storage.get(key);
        return value !== undefined ? value : null;
    }

    setItem<T>(key: string, value: T): T {
        this.storage.set(key, value);
        return value;
    }

    removeItem(key: string): void {
        this.storage.delete(key);
    }

    ready(): void {
        // No-op that exists only to satisfy the localForage interface.
    }

    config(): void {
        // No-op that exists only to satisfy the localForage interface.
    }
}

export const inMemoryStorage = new InMemoryStorage();
