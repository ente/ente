import type { StaffSession } from "./session";

export const apiOrigin =
    import.meta.env.VITE_ENTE_API_ORIGIN ?? "https://api.ente.com";

type QueryParamValue = string | number | boolean;

export const apiURL = (
    path: string,
    queryParams?: Record<string, QueryParamValue>,
) => {
    let url = apiOrigin + path;
    if (queryParams) {
        const stringParams = Object.fromEntries(
            Object.entries(queryParams).map(([key, value]) => [
                key,
                value.toString(),
            ]),
        );
        url = `${url}?${new URLSearchParams(stringParams).toString()}`;
    }
    return url;
};

export const requireEmail = ({ email }: Pick<StaffSession, "email">) => {
    if (!email) throw new Error("Email not found");
    return email;
};

export const requireToken = ({ token }: Pick<StaffSession, "token">) => {
    if (!token) throw new Error("Token not found");
    return token;
};

export const staffRequestHeaders = (session: Pick<StaffSession, "token">) => ({
    "X-Auth-Token": requireToken(session),
});

export const staffJSONRequestHeaders = (
    session: Pick<StaffSession, "token">,
) => ({ ...staffRequestHeaders(session), "Content-Type": "application/json" });

export const ensureOk = async (response: Response, fallback: string) => {
    if (!response.ok) {
        throw new Error(await responseErrorMessage(response, fallback));
    }
};

const responseErrorMessage = async (response: Response, fallback: string) => {
    const text = await response.text();
    if (!text) {
        return fallback;
    }

    try {
        const body = JSON.parse(text) as unknown;
        if (body && typeof body === "object" && "message" in body) {
            const { message } = body as { message?: unknown };
            if (typeof message === "string" && message) {
                return message;
            }
        }
    } catch {
        return text;
    }

    return fallback;
};
