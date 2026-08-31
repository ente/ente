import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";

const Session = z.object({
    token: z.string(),
    isCurrent: z.boolean().optional(),
    creationTime: z.number(),
    ip: z.string(),
    ua: z.string(),
    prettyUA: z.string(),
    lastUsedTime: z.number(),
});

export type Session = z.infer<typeof Session>;

export const isCurrentSession = (
    session: Session,
    currentToken: string | undefined,
) => session.isCurrent ?? session.token === currentToken;

const SessionsResponse = z.object({ sessions: z.array(Session) });

export const getActiveSessions = async (): Promise<Session[]> => {
    const res = await fetch(await apiURL("/users/sessions"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    const { sessions } = SessionsResponse.parse(await res.json());
    return sessions.sort((a, b) => b.lastUsedTime - a.lastUsedTime);
};

export const terminateSession = async (token: string): Promise<void> => {
    const url = await apiURL("/users/session");
    const res = await fetch(`${url}?token=${encodeURIComponent(token)}`, {
        method: "DELETE",
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
};
