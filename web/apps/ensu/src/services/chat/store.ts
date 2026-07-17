import { isTauriRuntime } from "@/services/tauri-runtime";
import { getKV, removeKV, setKV } from "ente-base/kv";
import log from "ente-base/log";
import { openDB, type DBSchema, type IDBPDatabase } from "idb";
import { decryptAttachmentBytes, encryptAttachmentBytes } from "./attachments";
import {
    decryptChatField,
    decryptChatPayload,
    encryptChatField,
    encryptChatPayload,
} from "./crypto";

const CHAT_DB_NAME = "ensu-chat";

export type AttachmentKind = "image" | "document";

export interface ChatAttachment {
    id: string;
    kind: AttachmentKind;
    name: string;
    size: number;
    encryptedName?: string;
}

export interface StoredAttachment {
    id: string;
    kind: AttachmentKind;
    size: number;
    encryptedName: string;
}

export interface StoredSession {
    sessionUuid: string;
    createdAt: number;
    updatedAt: number;
    encryptedData: string;
    header: string;
}

export interface StoredMessage {
    messageUuid: string;
    sessionUuid: string;
    parentMessageUuid?: string;
    sender: "self" | "assistant";
    createdAt: number;
    encryptedData: string;
    header: string;
    attachments?: StoredAttachment[];
}

interface StoredAttachmentBytes {
    id: string;
    data: Uint8Array<ArrayBuffer>;
}

interface ChatDbSchema {
    sessions: StoredSession;
    messages: StoredMessage;
    attachmentBytes: StoredAttachmentBytes;
}

type ChatStoreName = keyof ChatDbSchema;

interface IndexedChatDBSchema extends DBSchema {
    sessions: { key: string; value: StoredSession };
    messages: { key: string; value: StoredMessage };
    attachmentBytes: { key: string; value: StoredAttachmentBytes };
}

interface ChatObjectStore<K extends ChatStoreName> {
    get: (key: string) => Promise<ChatDbSchema[K] | undefined>;
    getAll: () => Promise<ChatDbSchema[K][]>;
    put: (value: ChatDbSchema[K]) => Promise<void>;
    delete: (key: string) => Promise<void>;
}

interface ChatTransaction {
    objectStore: <K extends ChatStoreName>(name: K) => ChatObjectStore<K>;
    done: Promise<void>;
}

interface ChatDbLike {
    get: <K extends ChatStoreName>(
        name: K,
        key: string,
    ) => Promise<ChatDbSchema[K] | undefined>;
    getAll: <K extends ChatStoreName>(name: K) => Promise<ChatDbSchema[K][]>;
    getAllKeys: (name: ChatStoreName) => Promise<string[]>;
    put: <K extends ChatStoreName>(
        name: K,
        value: ChatDbSchema[K],
    ) => Promise<void>;
    transaction: (names: ChatStoreName[], mode: "readwrite") => ChatTransaction;
    close: () => void;
}

export interface ChatSession {
    sessionUuid: string;
    rootSessionUuid: string;
    branchFromMessageUuid?: string;
    title: string;
    createdAt: number;
    updatedAt: number;
    lastMessagePreview?: string;
}

export interface ChatMessage {
    messageUuid: string;
    sessionUuid: string;
    parentMessageUuid?: string;
    sender: "self" | "assistant";
    text: string;
    createdAt: number;
    attachments?: ChatAttachment[];
    isSynthetic?: boolean;
}

interface NativeSession {
    sessionUuid: string;
    title: string;
    createdAt: number;
    updatedAt: number;
    lastMessagePreview?: string | null;
}

interface NativeAttachment {
    id: string;
    kind: AttachmentKind;
    name: string;
    size: number;
}

interface NativeMessage {
    messageUuid: string;
    sessionUuid: string;
    parentMessageUuid?: string | null;
    sender: "self" | "assistant";
    text: string;
    createdAt: number;
    attachments?: NativeAttachment[];
}

const nowMicros = () => Date.now() * 1000;

const formatLogError = (error: unknown) => {
    if (error instanceof Error) {
        const message = error.message || error.name;
        return error.stack ? `${message}\n${error.stack}` : message;
    }
    if (typeof error === "string") return error;
    try {
        return JSON.stringify(error);
    } catch {
        return String(error);
    }
};

const cloneStoreEntry = <K extends ChatStoreName>(
    name: K,
    value: ChatDbSchema[K],
): ChatDbSchema[K] => {
    if (name === "attachmentBytes") {
        const attachment = value as StoredAttachmentBytes;
        return {
            ...attachment,
            data: new Uint8Array(attachment.data),
        } as ChatDbSchema[K];
    }

    const cloned = { ...value };
    if (name === "messages") {
        const message = cloned as StoredMessage;
        message.attachments = message.attachments?.map((attachment) => ({
            ...attachment,
        }));
    }
    return cloned;
};

let _chatDb: Promise<ChatDbLike> | undefined;

const createIndexedDbChatDb = (
    db: IDBPDatabase<IndexedChatDBSchema>,
): ChatDbLike => ({
    get: async (name, key) => {
        const entry = (await db.get(name, key)) as
            | ChatDbSchema[typeof name]
            | undefined;
        if (!entry) return undefined;
        return cloneStoreEntry(name, entry);
    },
    getAll: async (name) => {
        const entries = (await db.getAll(name)) as ChatDbSchema[typeof name][];
        return entries.map((entry) => cloneStoreEntry(name, entry));
    },
    getAllKeys: async (name) => db.getAllKeys(name),
    put: async (name, value) => {
        await db.put(name, cloneStoreEntry(name, value));
    },
    transaction: (names, mode) => {
        const tx = db.transaction(names, mode);
        return {
            objectStore: <K extends ChatStoreName>(
                name: K,
            ): ChatObjectStore<K> => ({
                get: async (key) => {
                    const entry = (await tx.objectStore(name).get(key)) as
                        | ChatDbSchema[K]
                        | undefined;
                    if (!entry) return undefined;
                    return cloneStoreEntry(name, entry);
                },
                getAll: async () => {
                    const entries = (await tx
                        .objectStore(name)
                        .getAll()) as ChatDbSchema[K][];
                    return entries.map((entry) => cloneStoreEntry(name, entry));
                },
                put: async (value: ChatDbSchema[K]) => {
                    await tx
                        .objectStore(name)
                        .put(cloneStoreEntry(name, value));
                },
                delete: async (key: string) => {
                    await tx.objectStore(name).delete(key);
                },
            }),
            done: tx.done,
        };
    },
    close: () => db.close(),
});

const openChatDb = async () => {
    const db = await openDB<IndexedChatDBSchema>(CHAT_DB_NAME, 1, {
        upgrade(db) {
            if (!db.objectStoreNames.contains("sessions")) {
                db.createObjectStore("sessions", { keyPath: "sessionUuid" });
            }
            if (!db.objectStoreNames.contains("messages")) {
                db.createObjectStore("messages", { keyPath: "messageUuid" });
            }
            if (!db.objectStoreNames.contains("attachmentBytes")) {
                db.createObjectStore("attachmentBytes", { keyPath: "id" });
            }
        },
    });

    return createIndexedDbChatDb(db);
};

export const chatDb = () => (_chatDb ??= openChatDb());

const normalizeTitleText = (value: string) => value.replace(/\s+/g, " ").trim();

export const sessionTitleFromText = (value: string, fallback = "New chat") => {
    const normalized = normalizeTitleText(value);
    if (!normalized) return fallback;
    if (normalized.length <= 40) return normalized;
    return `${normalized.slice(0, 39)}…`;
};

const safeTitle = (value: unknown) =>
    typeof value === "string"
        ? sessionTitleFromText(value, "New chat")
        : "New chat";

export const decryptSessionTitleStrict = async (
    session: StoredSession,
    chatKey: string,
) => {
    const payload = (await decryptChatPayload(
        { encryptedData: session.encryptedData, header: session.header },
        chatKey,
    )) as { title?: string };
    return safeTitle(payload.title);
};

const decryptSessionTitle = (session: StoredSession, chatKey: string) =>
    decryptSessionTitleStrict(session, chatKey).catch((error: unknown) => {
        log.error("Failed to decrypt session payload", error);
        return "New chat";
    });

export const decryptMessageTextStrict = async (
    message: StoredMessage,
    chatKey: string,
) => {
    const payload = (await decryptChatPayload(
        { encryptedData: message.encryptedData, header: message.header },
        chatKey,
    )) as { text?: string };
    return typeof payload.text === "string" ? payload.text : "";
};

const decryptMessageText = (message: StoredMessage, chatKey: string) =>
    decryptMessageTextStrict(message, chatKey).catch((error: unknown) => {
        log.error("Failed to decrypt message payload", error);
        return "";
    });

const serializeAttachments = async (
    attachments: ChatAttachment[] = [],
    chatKey: string,
): Promise<StoredAttachment[]> => {
    if (!attachments.length) return [];
    if (!isTauriRuntime()) {
        log.warn(
            "Chat attachments are only supported in the desktop app; ignoring attachments on web.",
        );
        return [];
    }
    return Promise.all(
        attachments.map(async (attachment) => ({
            id: attachment.id,
            kind: attachment.kind,
            size: attachment.size,
            encryptedName:
                attachment.encryptedName ??
                (await encryptChatField(attachment.name, chatKey)),
        })),
    );
};

const deserializeAttachments = async (
    attachments: StoredAttachment[] | undefined,
    chatKey: string,
): Promise<ChatAttachment[]> => {
    if (!attachments?.length || !isTauriRuntime()) return [];

    return Promise.all(
        attachments.map(async (attachment) => {
            try {
                const name = await decryptChatField(
                    attachment.encryptedName,
                    chatKey,
                );
                return {
                    id: attachment.id,
                    kind: attachment.kind,
                    size: attachment.size,
                    name,
                    encryptedName: attachment.encryptedName,
                } satisfies ChatAttachment;
            } catch (error) {
                log.error("Failed to decrypt attachment name", error);
                return {
                    id: attachment.id,
                    kind: attachment.kind,
                    size: attachment.size,
                    name: "Attachment",
                    encryptedName: attachment.encryptedName,
                } satisfies ChatAttachment;
            }
        }),
    );
};

export const deserializeAttachmentsStrict = async (
    attachments: StoredAttachment[] | undefined,
    chatKey: string,
): Promise<ChatAttachment[]> =>
    Promise.all(
        (attachments ?? []).map(async (attachment) => ({
            id: attachment.id,
            kind: attachment.kind,
            size: attachment.size,
            name: await decryptChatField(attachment.encryptedName, chatKey),
        })),
    );

const fetchStore = async () => {
    const db = await chatDb();
    const [sessions, messages] = await Promise.all([
        db.getAll("sessions"),
        db.getAll("messages"),
    ]);
    return { sessions, messages };
};

export const invokeChat = async <T>(
    command: string,
    args?: Record<string, unknown>,
) => {
    const { invoke } = await import("@tauri-apps/api/core");
    return invoke<T>(command, args);
};

const listSessionsNative = async (): Promise<ChatSession[]> => {
    const sessions = await invokeChat<NativeSession[]>(
        "chat_db_list_sessions_with_preview",
    );

    return sessions.map((session) => ({
        sessionUuid: session.sessionUuid,
        rootSessionUuid: session.sessionUuid,
        branchFromMessageUuid: undefined,
        title: safeTitle(session.title),
        createdAt: session.createdAt,
        updatedAt: session.updatedAt,
        lastMessagePreview: session.lastMessagePreview ?? undefined,
    }));
};

const listMessagesNative = async (
    sessionUuid: string,
): Promise<ChatMessage[]> => {
    const messages = await invokeChat<NativeMessage[]>("chat_db_get_messages", {
        sessionUuid,
    });

    return messages.map((message) => ({
        messageUuid: message.messageUuid,
        sessionUuid: message.sessionUuid,
        parentMessageUuid: message.parentMessageUuid ?? undefined,
        sender: message.sender,
        text: message.text,
        createdAt: message.createdAt,
        attachments: message.attachments?.map((attachment) => ({
            id: attachment.id,
            kind: attachment.kind,
            name: attachment.name,
            size: attachment.size,
        })),
    }));
};

const createSessionNative = async () => {
    const session = await invokeChat<NativeSession>("chat_db_create_session", {
        title: "New chat",
    });
    return session.sessionUuid;
};

const updateSessionTitleNative = async (sessionUuid: string, title: string) => {
    await invokeChat("chat_db_update_session_title", { sessionUuid, title });
};

const addMessageNative = async (
    sessionUuid: string,
    sender: "self" | "assistant",
    text: string,
    parentMessageUuid?: string,
    attachments: ChatAttachment[] = [],
): Promise<ChatMessage> => {
    const message = await invokeChat<NativeMessage>("chat_db_insert_message", {
        input: {
            sessionUuid,
            sender,
            text,
            parentMessageUuid,
            attachments: attachments.map((attachment) => ({
                id: attachment.id,
                kind: attachment.kind,
                name: attachment.name,
                size: attachment.size,
            })),
        },
    });

    if (sender === "self") {
        try {
            const session = await invokeChat<NativeSession | null>(
                "chat_db_get_session",
                { sessionUuid },
            );
            if (
                session &&
                safeTitle(session.title).toLowerCase() === "new chat"
            ) {
                const title = sessionTitleFromText(text, "New chat");
                await updateSessionTitleNative(sessionUuid, title);
            }
        } catch (error) {
            log.error("Failed to update native session title", error);
        }
    }

    return {
        messageUuid: message.messageUuid,
        sessionUuid: message.sessionUuid,
        parentMessageUuid: message.parentMessageUuid ?? undefined,
        sender: message.sender,
        text: message.text,
        createdAt: message.createdAt,
        attachments: message.attachments?.map((attachment) => ({
            id: attachment.id,
            kind: attachment.kind,
            name: attachment.name,
            size: attachment.size,
        })),
    };
};

const updateMessageNative = async (messageUuid: string, text: string) => {
    await invokeChat("chat_db_update_message_text", { messageUuid, text });
};

const deleteSessionNative = async (sessionUuid: string) => {
    const attachmentIds = await invokeChat<string[]>("chat_db_delete_session", {
        sessionUuid,
    });
    for (const id of attachmentIds) {
        try {
            await deleteAttachmentBytes(id);
        } catch (error) {
            log.warn(`Failed to delete attachment payload ${id}`, error);
        }
    }
};

export const listSessions = async (chatKey: string): Promise<ChatSession[]> => {
    if (isTauriRuntime()) {
        try {
            return await listSessionsNative();
        } catch (error) {
            log.error(
                `Failed to list native sessions: ${formatLogError(error)}`,
            );
            throw error;
        }
    }

    try {
        const { sessions, messages } = await fetchStore();

        const activeSessions = sessions.sort(
            (a, b) => b.updatedAt - a.updatedAt,
        );

        const bySession = new Map<string, StoredMessage[]>();
        for (const message of messages) {
            const list = bySession.get(message.sessionUuid) ?? [];
            list.push(message);
            bySession.set(message.sessionUuid, list);
        }

        for (const list of bySession.values()) {
            list.sort((a, b) => b.createdAt - a.createdAt);
        }

        return Promise.all(
            activeSessions.map(async (session) => {
                const title = await decryptSessionTitle(session, chatKey);
                const latest = bySession.get(session.sessionUuid)?.[0];
                const lastMessagePreview = latest
                    ? await decryptMessageText(latest, chatKey)
                    : undefined;

                return {
                    sessionUuid: session.sessionUuid,
                    rootSessionUuid: session.sessionUuid,
                    branchFromMessageUuid: undefined,
                    title,
                    createdAt: session.createdAt,
                    updatedAt: session.updatedAt,
                    lastMessagePreview,
                } satisfies ChatSession;
            }),
        );
    } catch (error) {
        log.error(`Failed to list sessions: ${formatLogError(error)}`);
        throw error;
    }
};

export const listMessages = async (
    sessionUuid: string,
    chatKey: string,
): Promise<ChatMessage[]> => {
    if (isTauriRuntime()) {
        try {
            return await listMessagesNative(sessionUuid);
        } catch (error) {
            log.error(
                `Failed to list native messages: ${formatLogError(error)}`,
            );
            throw error;
        }
    }

    try {
        const { messages } = await fetchStore();
        const sessionMessages = messages
            .filter((message) => message.sessionUuid === sessionUuid)
            .sort((a, b) => a.createdAt - b.createdAt);

        return Promise.all(
            sessionMessages.map(async (message) => ({
                messageUuid: message.messageUuid,
                sessionUuid: message.sessionUuid,
                parentMessageUuid: message.parentMessageUuid,
                sender: message.sender,
                createdAt: message.createdAt,
                text: await decryptMessageText(message, chatKey),
                attachments: await deserializeAttachments(
                    message.attachments,
                    chatKey,
                ),
            })),
        );
    } catch (error) {
        log.error(`Failed to list messages: ${formatLogError(error)}`);
        throw error;
    }
};

export const createSession = async (chatKey: string) => {
    if (isTauriRuntime()) {
        return createSessionNative();
    }

    const db = await chatDb();
    const now = nowMicros();
    const sessionUuid = crypto.randomUUID();

    const encrypted = await encryptChatPayload({ title: "New chat" }, chatKey);

    const session: StoredSession = {
        sessionUuid,
        createdAt: now,
        updatedAt: now,
        encryptedData: encrypted.encryptedData,
        header: encrypted.header,
    };

    await db.put("sessions", session);
    return sessionUuid;
};

export const addMessage = async (
    sessionUuid: string,
    sender: "self" | "assistant",
    text: string,
    chatKey: string,
    parentMessageUuid?: string,
    attachments: ChatAttachment[] = [],
): Promise<ChatMessage> => {
    if (isTauriRuntime()) {
        return addMessageNative(
            sessionUuid,
            sender,
            text,
            parentMessageUuid,
            attachments,
        );
    }

    const db = await chatDb();
    const now = nowMicros();
    const messageUuid = crypto.randomUUID();

    const encrypted = await encryptChatPayload({ text }, chatKey);
    const storedAttachments = await serializeAttachments(attachments, chatKey);

    const message: StoredMessage = {
        messageUuid,
        sessionUuid,
        parentMessageUuid,
        sender,
        createdAt: now,
        encryptedData: encrypted.encryptedData,
        header: encrypted.header,
        attachments: storedAttachments,
    };

    const tx = db.transaction(["sessions", "messages"], "readwrite");
    await tx.objectStore("messages").put(message);

    const sessionStore = tx.objectStore("sessions");
    const session = await sessionStore.get(sessionUuid);
    if (session) {
        session.updatedAt = now;

        const currentTitle = await decryptSessionTitle(session, chatKey);
        if (sender === "self" && currentTitle.toLowerCase() === "new chat") {
            const title = sessionTitleFromText(text, "New chat");
            const updated = await encryptChatPayload({ title }, chatKey);
            session.encryptedData = updated.encryptedData;
            session.header = updated.header;
        }

        await sessionStore.put(session);
    }

    await tx.done;
    return {
        messageUuid,
        sessionUuid,
        parentMessageUuid,
        sender,
        text,
        createdAt: now,
        attachments,
    };
};

export const updateSessionTitle = async (
    sessionUuid: string,
    title: string,
    chatKey: string,
) => {
    const safe = sessionTitleFromText(title, "New chat");
    if (isTauriRuntime()) {
        await updateSessionTitleNative(sessionUuid, safe);
        return;
    }

    const db = await chatDb();
    const session = await db.get("sessions", sessionUuid);
    if (!session) return;

    const updated = await encryptChatPayload({ title: safe }, chatKey);
    session.encryptedData = updated.encryptedData;
    session.header = updated.header;
    session.updatedAt = nowMicros();
    await db.put("sessions", session);
};

export const updateMessage = async (
    messageUuid: string,
    text: string,
    chatKey: string,
) => {
    if (isTauriRuntime()) {
        await updateMessageNative(messageUuid, text);
        return;
    }

    const db = await chatDb();
    const tx = db.transaction(["sessions", "messages"], "readwrite");
    const messageStore = tx.objectStore("messages");
    const message = await messageStore.get(messageUuid);
    if (!message) {
        await tx.done;
        return;
    }

    const encrypted = await encryptChatPayload({ text }, chatKey);
    message.encryptedData = encrypted.encryptedData;
    message.header = encrypted.header;
    await messageStore.put(message);

    const sessionStore = tx.objectStore("sessions");
    const session = await sessionStore.get(message.sessionUuid);
    if (session) {
        session.updatedAt = nowMicros();
        await sessionStore.put(session);
    }

    await tx.done;
};

const branchSelectionsKey = (rootSessionUuid: string) =>
    `ensu.chat.branchSelections.v1.${rootSessionUuid}`;

export const getBranchSelections = async (rootSessionUuid: string) => {
    const stored = await getKV(branchSelectionsKey(rootSessionUuid));
    if (!stored || typeof stored !== "object") return {};

    return Object.fromEntries(
        Object.entries(stored).filter(
            (entry): entry is [string, string] =>
                typeof entry[0] === "string" && typeof entry[1] === "string",
        ),
    );
};

export const setBranchSelection = async (
    rootSessionUuid: string,
    selectionKey: string,
    selectedMessageUuid: string,
) => {
    const selections = await getBranchSelections(rootSessionUuid);
    selections[selectionKey] = selectedMessageUuid;
    await setKV(branchSelectionsKey(rootSessionUuid), selections);
};

export const deleteBranchSelections = (rootSessionUuid: string) =>
    removeKV(branchSelectionsKey(rootSessionUuid));

export const deleteSession = async (sessionUuid: string) => {
    if (isTauriRuntime()) {
        await deleteSessionNative(sessionUuid);
        await deleteBranchSelections(sessionUuid);
        return;
    }

    const db = await chatDb();
    const messages = await db.getAll("messages");
    const sessionMessages = messages.filter(
        (message) => message.sessionUuid === sessionUuid,
    );
    const attachmentIds = new Set(
        sessionMessages.flatMap((message) =>
            (message.attachments ?? []).map((attachment) => attachment.id),
        ),
    );
    const tx = db.transaction(
        ["sessions", "messages", "attachmentBytes"],
        "readwrite",
    );
    const sessionStore = tx.objectStore("sessions");
    const messageStore = tx.objectStore("messages");
    const attachmentStore = tx.objectStore("attachmentBytes");
    await Promise.all([
        sessionStore.delete(sessionUuid),
        ...sessionMessages.map((message) =>
            messageStore.delete(message.messageUuid),
        ),
        ...[...attachmentIds].map((id) => attachmentStore.delete(id)),
    ]);

    await tx.done;
    await deleteBranchSelections(sessionUuid);
};

let _attachmentDir: Promise<string> | undefined;

const attachmentDir = async () => {
    if (!isTauriRuntime()) {
        return "";
    }

    _attachmentDir ??= (async () => {
        const { appDataDir, join } = await import("@tauri-apps/api/path");
        const { mkdir } = await import("@tauri-apps/plugin-fs");
        const root = await appDataDir();
        const dir = await join(root, "ensu_llmchat_attachments_v2");
        await mkdir(dir, { recursive: true });
        return dir;
    })();

    return _attachmentDir;
};

const attachmentPath = async (id: string) => {
    const { join } = await import("@tauri-apps/api/path");
    const dir = await attachmentDir();
    return join(dir, id);
};

export const writeAttachmentBytes = async (
    id: string,
    data: Uint8Array<ArrayBuffer>,
) => {
    if (isTauriRuntime()) {
        const { writeFile } = await import("@tauri-apps/plugin-fs");
        await writeFile(await attachmentPath(id), data);
        return;
    }

    const db = await chatDb();
    await db.put("attachmentBytes", { id, data });
};

export const deleteAttachmentBytes = async (id: string) => {
    if (isTauriRuntime()) {
        const { exists, remove } = await import("@tauri-apps/plugin-fs");
        const path = await attachmentPath(id);
        if (await exists(path)) await remove(path);
        return;
    }

    const db = await chatDb();
    const tx = db.transaction(["attachmentBytes"], "readwrite");
    await tx.objectStore("attachmentBytes").delete(id);
    await tx.done;
};

export const storeEncryptedAttachmentBytes = async (
    id: string,
    data: Uint8Array,
    chatKey: string,
    sessionUuid: string,
) => {
    const encrypted = await encryptAttachmentBytes(data, chatKey, sessionUuid);
    await writeAttachmentBytes(id, encrypted);
};

export const readAttachmentBytes = async (
    id: string,
): Promise<Uint8Array<ArrayBuffer>> => {
    if (isTauriRuntime()) {
        const { readFile } = await import("@tauri-apps/plugin-fs");
        const path = await attachmentPath(id);
        return readFile(path);
    }

    const db = await chatDb();
    const entry = await db.get("attachmentBytes", id);
    if (!entry) {
        throw new Error(`Attachment bytes not found: ${id}`);
    }
    return entry.data instanceof Uint8Array
        ? entry.data
        : new Uint8Array(entry.data);
};

export const readDecryptedAttachmentBytes = async (
    id: string,
    chatKey: string,
    sessionUuid: string,
): Promise<Uint8Array<ArrayBuffer>> => {
    const encrypted = await readAttachmentBytes(id);
    return decryptAttachmentBytes(encrypted, chatKey, sessionUuid);
};

export const attachmentBytesExists = async (id: string): Promise<boolean> => {
    if (isTauriRuntime()) {
        const { exists } = await import("@tauri-apps/plugin-fs");
        const path = await attachmentPath(id);
        return exists(path);
    }

    const db = await chatDb();
    const entry = await db.get("attachmentBytes", id);
    return !!entry;
};
