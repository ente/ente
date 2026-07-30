import { base64ToBytes } from "@/services/base64";
import { isTauriRuntime } from "@/services/tauri-runtime";
import { removeKV } from "ente-base/kv";
import log from "ente-base/log";
import { deleteDB, openDB, type DBSchema } from "idb";
import {
    secureStorageDelete,
    secureStorageGet,
    secureStorageSet,
} from "../secure-storage";
import { decryptAttachmentBytes, encryptAttachmentBytes } from "./attachments";
import {
    attachmentBytesExists,
    chatDb,
    decryptMessageTextStrict,
    decryptSessionTitleStrict,
    deleteAttachmentBytes,
    deserializeAttachmentsStrict,
    invokeChat,
    readAttachmentBytes,
    writeAttachmentBytes,
    type StoredAttachment,
    type StoredMessage,
    type StoredSession,
} from "./store";

const LOCAL_STORAGE_STORE = "ensu.chat.store.v1";
const TOMBSTONE_MIGRATION = "ensu.chat.localMigration.v2";
const OLD_INDEXED_DB = "ensu.chat.db";
const MIGRATION_DONE = "ensu.chat.localMigration.v3";
const OLD_LOCAL_SECURE_KEY = "localChatKey";
const OLD_LOCAL_BROWSER_KEY = "ensu.chatKey.local";
const OLD_REMOTE_BROWSER_KEY = "ensu.chatKey";
const KEY_FILE = "chat-keys.json";
const LEGACY_ATTACHMENT_SECURE_KEY = "legacyAttachmentKey.v2";

type OldSession = StoredSession & {
    deletedAt?: number | null;
    isDeleted?: boolean;
};
type OldMessage = Omit<StoredMessage, "attachments"> & {
    attachments?: (StoredAttachment & { uploadedAt?: number | null })[];
    deletedAt?: number | null;
    isDeleted?: boolean;
};
type AttachmentBytes = { id: string; data: Uint8Array<ArrayBuffer> };
type BrowserStore = {
    sessions: OldSession[];
    messages: OldMessage[];
    attachmentBytes: AttachmentBytes[];
};

interface OldIndexedDb extends DBSchema {
    sessions: { key: string; value: OldSession };
    messages: { key: string; value: OldMessage };
    attachmentBytes: { key: string; value: AttachmentBytes };
}

let _migrationSourceKeys: string[] = [];

const localGet = (key: string) => localStorage.getItem(key) ?? undefined;

const keyFilePath = async () => {
    const { appDataDir, join } = await import("@tauri-apps/api/path");
    return join(await appDataDir(), KEY_FILE);
};

const readKeyFile = async () => {
    const [{ exists, readFile }, path] = await Promise.all([
        import("@tauri-apps/plugin-fs"),
        keyFilePath(),
    ]);
    if (!(await exists(path))) return undefined;
    try {
        const value = JSON.parse(
            new TextDecoder().decode(await readFile(path)),
        ) as { localChatKey?: unknown };
        return typeof value.localChatKey === "string"
            ? value.localChatKey
            : undefined;
    } catch {
        return undefined;
    }
};

const isLocalChatMigrationDone = () => localGet(MIGRATION_DONE) === "1";

export const promoteLocalChatKey = async (
    current: string | undefined,
    currentSecureKey: string,
    browserKey: string,
) => {
    if (isLocalChatMigrationDone()) {
        _migrationSourceKeys = current ? [current] : [];
        return current;
    }
    const [oldSecure, file] = await Promise.all([
        secureStorageGet(OLD_LOCAL_SECURE_KEY),
        readKeyFile(),
    ]);
    _migrationSourceKeys = [
        current,
        localGet(browserKey),
        oldSecure,
        file,
    ].filter(
        (key, index, keys): key is string =>
            !!key && keys.indexOf(key) === index,
    );
    const key = _migrationSourceKeys[0];
    if (key && key !== current) await secureStorageSet(currentSecureKey, key);
    return key;
};

export const hasRetiredLocalChatStore = () => !!localGet(LOCAL_STORAGE_STORE);

const retiredUserID = () => {
    try {
        const user = JSON.parse(localStorage.getItem("user") ?? "null") as {
            id?: unknown;
        } | null;
        return typeof user?.id === "number" ? user.id : undefined;
    } catch {
        return undefined;
    }
};

export const retiredBrowserChatKey = () => {
    if (typeof localStorage === "undefined") return undefined;
    const userID = retiredUserID();
    const names = [
        OLD_REMOTE_BROWSER_KEY,
        ...(userID ? [`${OLD_REMOTE_BROWSER_KEY}.${userID}`] : []),
        ...Object.keys(localStorage).filter(
            (key) =>
                key.startsWith(`${OLD_REMOTE_BROWSER_KEY}.`) &&
                key !== OLD_LOCAL_BROWSER_KEY,
        ),
    ];
    return names.map(localGet).find(Boolean);
};

const finalizeLocalChatMigration = async () => {
    try {
        const userID = retiredUserID();
        localStorage.removeItem(LOCAL_STORAGE_STORE);
        await Promise.all(
            [
                "masterKey",
                "remoteChatKey",
                ...(userID
                    ? [`remoteChatKey.${userID}`, `remoteChatKey.v2.${userID}`]
                    : []),
                OLD_LOCAL_SECURE_KEY,
                LEGACY_ATTACHMENT_SECURE_KEY,
            ].map(secureStorageDelete),
        );

        const [{ exists, remove }, { appDataDir, join }] = await Promise.all([
            import("@tauri-apps/plugin-fs"),
            import("@tauri-apps/api/path"),
        ]);
        const keyFile = await join(await appDataDir(), KEY_FILE);
        if (await exists(keyFile)) await remove(keyFile);

        for (const key of Object.keys(localStorage)) {
            if (key.startsWith("ensu.chatKey")) localStorage.removeItem(key);
        }
        [
            "user",
            "srpAttributes",
            "keyAttributes",
            "originalKeyAttributes",
            "isFirstLogin",
            "ensu.chat.nativeMigration.v2",
        ].forEach((key) => localStorage.removeItem(key));
        await removeKV("token");
    } catch (error) {
        log.warn("Could not finish cleaning up old chat storage", error);
    }
    localStorage.setItem(MIGRATION_DONE, "1");
};

const liveStore = (
    sessions: OldSession[],
    messages: OldMessage[],
    attachmentBytes: AttachmentBytes[],
): BrowserStore => {
    const liveSessions = sessions.filter(
        ({ deletedAt, isDeleted }) => !deletedAt && !isDeleted,
    );
    const sessionIDs = new Set(
        liveSessions.map(({ sessionUuid }) => sessionUuid),
    );
    return {
        sessions: liveSessions,
        messages: messages.filter(
            ({ sessionUuid, deletedAt, isDeleted }) =>
                !deletedAt && !isDeleted && sessionIDs.has(sessionUuid),
        ),
        attachmentBytes,
    };
};

const localStorageStore = (): BrowserStore => {
    const json = localStorage.getItem(LOCAL_STORAGE_STORE);
    if (!json) return { sessions: [], messages: [], attachmentBytes: [] };
    try {
        const parsed = JSON.parse(json) as Partial<{
            sessions: OldSession[];
            messages: OldMessage[];
            attachmentBytes: { id: string; data: string }[];
        }>;
        return liveStore(
            parsed.sessions ?? [],
            parsed.messages ?? [],
            (parsed.attachmentBytes ?? []).map(({ id, data }) => ({
                id,
                data: base64ToBytes(data),
            })),
        );
    } catch (error) {
        log.warn("Ignoring an unreadable old local chat store", error);
        return { sessions: [], messages: [], attachmentBytes: [] };
    }
};

const hasLocalStorageStore = () => !!localStorage.getItem(LOCAL_STORAGE_STORE);

const writeBrowserStore = async (source: BrowserStore) => {
    const db = await chatDb();
    const [sessions, messages, attachmentKeys] = await Promise.all([
        db.getAll("sessions"),
        db.getAll("messages"),
        db.getAllKeys("attachmentBytes"),
    ]);
    const sessionIDs = new Set(sessions.map(({ sessionUuid }) => sessionUuid));
    const messageIDs = new Set(messages.map(({ messageUuid }) => messageUuid));
    const attachmentIDs = new Set(attachmentKeys);
    const tx = db.transaction(
        ["sessions", "messages", "attachmentBytes"],
        "readwrite",
    );
    await Promise.all([
        ...source.sessions
            .filter(({ sessionUuid }) => !sessionIDs.has(sessionUuid))
            .map((session) => tx.objectStore("sessions").put(session)),
        ...source.messages
            .filter(({ messageUuid }) => !messageIDs.has(messageUuid))
            .map((message) => tx.objectStore("messages").put(message)),
        ...source.attachmentBytes
            .filter(({ id }) => !attachmentIDs.has(id))
            .map((attachment) =>
                tx.objectStore("attachmentBytes").put(attachment),
            ),
        tx.done,
    ]);
};

const removeCurrentBrowserTombstones = async () => {
    if (localStorage.getItem(TOMBSTONE_MIGRATION) === "1") return;
    const db = await chatDb();
    const [sessions, messages] = await Promise.all([
        db.getAll("sessions") as Promise<OldSession[]>,
        db.getAll("messages") as Promise<OldMessage[]>,
    ]);
    const deletedSessions = new Set(
        sessions
            .filter(({ deletedAt, isDeleted }) => deletedAt || isDeleted)
            .map(({ sessionUuid }) => sessionUuid),
    );
    const deletedMessages = messages.filter(
        ({ sessionUuid, deletedAt, isDeleted }) =>
            deletedAt || isDeleted || deletedSessions.has(sessionUuid),
    );
    const tx = db.transaction(["sessions", "messages"], "readwrite");
    await Promise.all([
        ...[...deletedSessions].map((id) =>
            tx.objectStore("sessions").delete(id),
        ),
        ...deletedMessages.map(({ messageUuid }) =>
            tx.objectStore("messages").delete(messageUuid),
        ),
        tx.done,
    ]);
    localStorage.setItem(TOMBSTONE_MIGRATION, "1");
};

const readOldIndexedDb = async () => {
    let created = false;
    const source = await openDB<OldIndexedDb>(OLD_INDEXED_DB, undefined, {
        upgrade: () => {
            created = true;
        },
    });
    if (created || !source.objectStoreNames.contains("sessions")) {
        source.close();
        await deleteDB(OLD_INDEXED_DB);
        return undefined;
    }
    try {
        return liveStore(
            await source.getAll("sessions"),
            await source.getAll("messages"),
            await source.getAll("attachmentBytes"),
        );
    } finally {
        source.close();
    }
};

const importOldBrowserStores = async () => {
    if (isLocalChatMigrationDone()) return;
    if (hasLocalStorageStore()) {
        await writeBrowserStore(localStorageStore());
        localStorage.removeItem(LOCAL_STORAGE_STORE);
        return;
    }

    const source = await readOldIndexedDb();
    if (source) {
        await writeBrowserStore(source);
        await deleteDB(OLD_INDEXED_DB, {
            blocked: () => log.warn("Waiting for the old chat DB to close"),
        });
    }
    localStorage.setItem(MIGRATION_DONE, "1");
};

const localStorageSourceKey = async (
    source: BrowserStore,
    sourceKeys: string[],
) => {
    for (const key of sourceKeys) {
        try {
            if (source.sessions[0]) {
                await decryptSessionTitleStrict(source.sessions[0], key);
            } else if (source.messages[0]) {
                await decryptMessageTextStrict(source.messages[0], key);
            }
            return key;
        } catch {
            // Try the next migration-only key.
        }
    }
    throw new Error("No stored key could decrypt the old local chat store");
};

const importLocalStorageToNative = async (sourceKeys: string[]) => {
    const source = localStorageStore();
    const sourceKey = await localStorageSourceKey(source, sourceKeys);
    for (const session of source.sessions.sort(
        (left, right) => left.createdAt - right.createdAt,
    )) {
        await invokeChat("chat_db_upsert_session", {
            input: {
                sessionUuid: session.sessionUuid,
                title: await decryptSessionTitleStrict(session, sourceKey),
                createdAt: session.createdAt,
                updatedAt: session.updatedAt,
            },
        });
    }
    for (const message of source.messages.sort(
        (left, right) => left.createdAt - right.createdAt,
    )) {
        const attachments = await deserializeAttachmentsStrict(
            message.attachments,
            sourceKey,
        );
        await invokeChat("chat_db_insert_message_with_uuid", {
            input: {
                messageUuid: message.messageUuid,
                sessionUuid: message.sessionUuid,
                parentMessageUuid: message.parentMessageUuid ?? null,
                sender: message.sender,
                text: await decryptMessageTextStrict(message, sourceKey),
                createdAt: message.createdAt,
                attachments: attachments.map(({ id, kind, name, size }) => ({
                    id,
                    kind,
                    name,
                    size,
                })),
            },
        });
    }
    for (const { id, data } of source.attachmentBytes) {
        await writeAttachmentBytes(id, data);
    }
};

const distinctKeys = (keys: (string | undefined)[]) =>
    keys.filter(
        (key, index, values): key is string =>
            !!key && values.indexOf(key) === index,
    );

const decryptAttachmentWith = async (
    encrypted: Uint8Array,
    keys: string[],
    sessionUuid: string,
) => {
    for (const key of keys) {
        try {
            return [
                await decryptAttachmentBytes(encrypted, key, sessionUuid),
                key,
            ] as const;
        } catch {
            // Try the next migration-only key.
        }
    }
    return undefined;
};

const reencryptAttachment = async (
    id: string,
    sessionUuid: string,
    chatKey: string,
    candidates: string[],
) => {
    const stagingID = `${id}.migrating`;
    if (await attachmentBytesExists(stagingID)) {
        const staged = await readAttachmentBytes(stagingID);
        if (await decryptAttachmentWith(staged, [chatKey], sessionUuid)) {
            await writeAttachmentBytes(id, staged);
            await decryptAttachmentBytes(
                await readAttachmentBytes(id),
                chatKey,
                sessionUuid,
            );
            await deleteAttachmentBytes(stagingID);
            return;
        }
        await deleteAttachmentBytes(stagingID);
    }
    if (!(await attachmentBytesExists(id))) return;

    const decrypted = await decryptAttachmentWith(
        await readAttachmentBytes(id),
        candidates,
        sessionUuid,
    );
    if (!decrypted) {
        log.warn(`No stored key can decrypt attachment ${id}`);
        return;
    }
    const [plaintext, key] = decrypted;
    if (key === chatKey) return;

    await writeAttachmentBytes(
        stagingID,
        await encryptAttachmentBytes(plaintext, chatKey, sessionUuid),
    );
    const staged = await readAttachmentBytes(stagingID);
    await decryptAttachmentBytes(staged, chatKey, sessionUuid);
    await writeAttachmentBytes(id, staged);
    await decryptAttachmentBytes(
        await readAttachmentBytes(id),
        chatKey,
        sessionUuid,
    );
    await deleteAttachmentBytes(stagingID);
};

const reencryptAttachments = async (chatKey: string, sourceKeys: string[]) => {
    const legacyAttachmentKey = await secureStorageGet(
        LEGACY_ATTACHMENT_SECURE_KEY,
    ).catch((error: unknown) => {
        log.warn("Could not read the old attachment key", error);
        return undefined;
    });
    const candidates = distinctKeys([...sourceKeys, legacyAttachmentKey]);

    for (const { sessionUuid } of await invokeChat<{ sessionUuid: string }[]>(
        "chat_db_list_sessions",
    )) {
        for (const { id } of (
            await invokeChat<{ attachments?: { id: string }[] }[]>(
                "chat_db_get_messages",
                { sessionUuid },
            )
        ).flatMap(({ attachments }) => attachments ?? [])) {
            await reencryptAttachment(
                id,
                sessionUuid,
                chatKey,
                candidates,
            ).catch((error: unknown) =>
                log.warn(`Could not migrate attachment ${id}`, error),
            );
        }
    }
};

export const openChatStoreWithCompatibility = async (chatKey: string) => {
    if (isTauriRuntime()) {
        const migrationPending = !isLocalChatMigrationDone();
        const sourceKeys = distinctKeys([
            chatKey,
            ...(migrationPending ? _migrationSourceKeys : []),
        ]);
        const migrated = await invokeChat<boolean>("chat_db_open", {
            input: { keyB64: chatKey, recoveryKeysB64: sourceKeys },
        });
        if (migrationPending) {
            if (!migrated) return;
            if (hasLocalStorageStore()) {
                try {
                    await importLocalStorageToNative(sourceKeys);
                } catch (error) {
                    log.warn(
                        "Could not import the old local chat store",
                        error,
                    );
                    return;
                }
            }
            await reencryptAttachments(chatKey, sourceKeys);
            await finalizeLocalChatMigration();
        }
    } else {
        await importOldBrowserStores();
        await removeCurrentBrowserTombstones();
    }
};
