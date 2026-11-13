import { getKV, getKVN, setKV } from "ente-base/kv";
import { z } from "zod";
import type { ContactDisplayRecord, WrappedRootContactKey } from "./types";

const contactsKey = (sessionKey: string) => `contacts/${sessionKey}/records`;
const wrappedRootContactKeyKey = (sessionKey: string) =>
    `contacts/${sessionKey}/root-key`;
const sinceTimeKey = (sessionKey: string) =>
    `contacts/${sessionKey}/since-time`;

const ContactDisplayRecordZ = z.object({
    contactId: z.string(),
    contactUserId: z.number(),
    resolvedEmail: z.string().optional(),
    displayName: z.string().optional(),
    profilePictureAttachmentID: z.string().optional(),
    updatedAt: z.number(),
});

const WrappedRootContactKeyZ = z.object({
    encryptedKey: z.string(),
    header: z.string(),
});

export const savedContactDisplayRecords = async (
    sessionKey: string,
): Promise<ContactDisplayRecord[]> =>
    ContactDisplayRecordZ.array()
        .parse((await getKV(contactsKey(sessionKey))) ?? [])
        .map((record) => ({
            contactId: record.contactId,
            contactUserId: record.contactUserId,
            resolvedEmail: record.resolvedEmail,
            displayName: record.displayName,
            profilePictureAttachmentID: record.profilePictureAttachmentID,
            updatedAt: record.updatedAt,
        }));

export const saveContactDisplayRecords = (
    sessionKey: string,
    records: ContactDisplayRecord[],
) => setKV(contactsKey(sessionKey), records);

export const savedWrappedRootContactKey = async (
    sessionKey: string,
): Promise<WrappedRootContactKey | undefined> => {
    const saved = await getKV(wrappedRootContactKeyKey(sessionKey));
    return saved ? WrappedRootContactKeyZ.parse(saved) : undefined;
};

export const saveWrappedRootContactKey = (
    sessionKey: string,
    wrappedRootContactKey: WrappedRootContactKey,
) => setKV(wrappedRootContactKeyKey(sessionKey), wrappedRootContactKey);

export const savedContactsSinceTime = (sessionKey: string) =>
    getKVN(sinceTimeKey(sessionKey));

export const saveContactsSinceTime = (sessionKey: string, sinceTime: number) =>
    setKV(sinceTimeKey(sessionKey), sinceTime);
