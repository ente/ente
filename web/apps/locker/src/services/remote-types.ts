import type {
    LockerCollectionParticipant,
    LockerCollectionParticipantRole,
} from "@/types";
import { z } from "zod";

export const RemoteCollectionUserSchema = z.object({
    id: z.number(),
    email: z.string().nullish(),
    role: z.string().nullish(),
});

export type RemoteCollectionUser = z.infer<typeof RemoteCollectionUserSchema>;

export const RemoteIDResponseSchema = z.object({ id: z.number() });

export const RemoteCollectionCreateResponseSchema = z.object({
    collection: z.object({ id: z.number() }),
});

export const RemoteUploadURLResponseSchema = z.object({
    objectKey: z.string(),
    url: z.string(),
});

export const toLockerCollectionParticipant = (
    user: RemoteCollectionUser,
): LockerCollectionParticipant => ({
    id: user.id,
    email: user.email ?? undefined,
    role: user.role
        ? (user.role.toUpperCase() as LockerCollectionParticipantRole)
        : undefined,
});
