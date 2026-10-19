import {
    ChatSourceSelectionStore,
    type ChatSourceSelection,
} from "@/services/chat/source-selection";
import log from "ente-base/log";
import { useCallback, useEffect, useRef, useState } from "react";

export const useChatSources = (
    available: ChatSourceSelection,
    packInventoryReady: boolean,
    notesInventoryReady: boolean,
) => {
    const [, setRevision] = useState(0);
    const [packSettingsReady, setPackSettingsReady] = useState(false);
    const storeRef = useRef<ChatSourceSelectionStore | null>(null);
    if (!storeRef.current) {
        storeRef.current = new ChatSourceSelectionStore(
            typeof window === "undefined" ? undefined : window.localStorage,
            (error) => log.warn("Failed to persist chat sources", error),
        );
    }
    const store = storeRef.current;
    const inventoryReady =
        packInventoryReady && packSettingsReady && notesInventoryReady;
    const selection = inventoryReady ? store.selection(available) : undefined;
    useEffect(() => {
        if (!packInventoryReady) return;
        store.migratePackSettings(available.packIds);
        setPackSettingsReady(true);
    }, [available.packIds, packInventoryReady, store]);

    const setPackEnabled = useCallback(
        (id: string, enabled: boolean) => {
            if (!packInventoryReady) return;
            store.setPackEnabled(id, enabled, available.packIds);
            setRevision((value) => value + 1);
        },
        [available.packIds, packInventoryReady, store],
    );
    const setNoteEnabled = useCallback(
        (id: string, enabled: boolean) => {
            store.setNoteEnabled(id, enabled);
            setRevision((value) => value + 1);
        },
        [store],
    );

    return {
        selection,
        packSettingsReady: packInventoryReady && packSettingsReady,
        disabledNoteIds: store.disabledNoteIds(),
        disabledPackIds: store.disabledPackIds(),
        setPackEnabled,
        setNoteEnabled,
    };
};
