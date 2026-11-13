export interface ChatSourceSelection {
    packIds: string[];
    noteCollectionIds: string[];
}

type SelectionStorage = Pick<Storage, "getItem" | "setItem">;
const packsSettingsKey = "ensu.desktop.packs.disabledByDefault";
const notesSettingsKey = "ensu.desktop.notes.disabledByDefault";
const legacyPacksKey = "ensu.desktop.enabledKnowledgePacks";

const stringIds = (value: unknown): string[] | undefined =>
    Array.isArray(value) && value.every((id) => typeof id === "string")
        ? [...new Set(value)]
        : undefined;

export class ChatSourceSelectionStore {
    private cachedDisabledNoteIds?: string[];
    private cachedDisabledPackIds?: string[];
    private packSettingsMigrated = false;

    constructor(
        private storage?: SelectionStorage,
        private onError: (error: unknown) => void = () => undefined,
    ) {}

    private legacyPackIds(): string[] | undefined {
        try {
            const raw = this.storage?.getItem(legacyPacksKey);
            return raw ? stringIds(JSON.parse(raw)) : undefined;
        } catch (error) {
            this.onError(error);
            return undefined;
        }
    }

    migratePackSettings(packIds: string[]) {
        try {
            if (this.storage?.getItem(packsSettingsKey) != null) return;
            if (!this.packSettingsMigrated) {
                const legacy = this.legacyPackIds();
                if (!legacy) return;
                this.cachedDisabledPackIds = packIds.filter(
                    (id) => !legacy.includes(id),
                );
                this.packSettingsMigrated = true;
            }
            this.storage?.setItem(
                packsSettingsKey,
                JSON.stringify(this.cachedDisabledPackIds),
            );
        } catch (error) {
            this.onError(error);
        }
    }

    disabledPackIds(): string[] {
        if (this.cachedDisabledPackIds) return this.cachedDisabledPackIds;
        try {
            const raw = this.storage?.getItem(packsSettingsKey);
            this.cachedDisabledPackIds = raw
                ? (stringIds(JSON.parse(raw)) ?? [])
                : [];
        } catch (error) {
            this.onError(error);
            this.cachedDisabledPackIds = [];
        }
        return this.cachedDisabledPackIds;
    }

    setPackEnabled(id: string, enabled: boolean, availablePackIds: string[]) {
        this.migratePackSettings(availablePackIds);
        const ids = new Set(this.disabledPackIds());
        if (enabled) ids.delete(id);
        else ids.add(id);
        this.cachedDisabledPackIds = [...ids];
        try {
            this.storage?.setItem(
                packsSettingsKey,
                JSON.stringify(this.cachedDisabledPackIds),
            );
        } catch (error) {
            this.onError(error);
        }
    }

    selection(available: ChatSourceSelection): ChatSourceSelection {
        return {
            packIds: available.packIds.filter(
                (id) => !this.disabledPackIds().includes(id),
            ),
            noteCollectionIds: available.noteCollectionIds.filter(
                (id) => !this.disabledNoteIds().includes(id),
            ),
        };
    }

    disabledNoteIds(): string[] {
        if (this.cachedDisabledNoteIds) return this.cachedDisabledNoteIds;
        try {
            const raw = this.storage?.getItem(notesSettingsKey);
            this.cachedDisabledNoteIds = raw
                ? (stringIds(JSON.parse(raw)) ?? [])
                : [];
        } catch (error) {
            this.onError(error);
            this.cachedDisabledNoteIds = [];
        }
        return this.cachedDisabledNoteIds;
    }

    setNoteEnabled(id: string, enabled: boolean) {
        const ids = new Set(this.disabledNoteIds());
        if (enabled) ids.delete(id);
        else ids.add(id);
        this.cachedDisabledNoteIds = [...ids];
        try {
            this.storage?.setItem(
                notesSettingsKey,
                JSON.stringify(this.cachedDisabledNoteIds),
            );
        } catch (error) {
            this.onError(error);
        }
    }
}
