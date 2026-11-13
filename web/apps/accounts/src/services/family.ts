import { ensureOk, publicRequestHeaders } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";

const FamilyInviteInfo = z.object({ adminEmail: z.string() });

export type FamilyInviteInfo = z.infer<typeof FamilyInviteInfo>;

export const getFamilyInviteInfo = async (token: string) => {
    const res = await fetch(
        await apiURL(`/family/invite-info/${encodeURIComponent(token)}`),
        { headers: publicRequestHeaders() },
    );
    ensureOk(res);
    return FamilyInviteInfo.parse(await res.json());
};

export const acceptFamilyInvite = async (token: string) => {
    const res = await fetch(await apiURL("/family/accept-invite"), {
        method: "POST",
        headers: {
            ...publicRequestHeaders(),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ token }),
    });
    ensureOk(res);
    return FamilyInviteInfo.parse(await res.json());
};
