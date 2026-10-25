// Adapted from `web/apps/auth/src/services/code.ts`.
import { HOTP, TOTP } from "otpauth";
import { z } from "zod";
import { Steam } from "./steam";

export interface Code {
    id: string;
    type: "totp" | "hotp" | "steam";
    account?: string;
    issuer: string;
    length: number;
    period: number;
    algorithm: "sha1" | "sha256" | "sha512";
    counter?: number;
    secret: string;
    codeDisplay: CodeDisplay | undefined;
    uriString: string;
}

interface CodeDisplay {
    trashed?: boolean;
    pinned?: boolean;
    note?: string;
}

const CodeDisplay = z.object({
    trashed: z
        .boolean()
        .nullish()
        .transform((v) => v ?? undefined),
    pinned: z
        .boolean()
        .nullish()
        .transform((v) => v ?? undefined),
    note: z
        .string()
        .nullish()
        .transform((v) => v ?? undefined),
});

export const codeFromURIString = (id: string, uriString: string): Code => {
    try {
        return _codeFromURIString(id, uriString);
    } catch (e) {
        // Account names in legacy encodings can contain a raw "#".
        if (uriString.includes("#"))
            return _codeFromURIString(id, uriString.replaceAll("#", "%23"));
        throw e;
    }
};

const _codeFromURIString = (id: string, uriString: string): Code => {
    const url = new URL(uriString);
    const [type, path] = parsePathname(url);
    return {
        id,
        type,
        account: parseAccount(path),
        issuer: parseIssuer(url, path),
        length: parseLength(url, type),
        period: parsePeriod(url),
        algorithm: parseAlgorithm(url),
        counter: parseCounter(url),
        secret: parseSecret(url),
        codeDisplay: parseCodeDisplay(url),
        uriString,
    };
};

const parsePathname = (url: URL): [type: Code["type"], path: string] => {
    switch (url.host.toLowerCase()) {
        case "totp":
            return ["totp", url.pathname];
        case "hotp":
            return ["hotp", url.pathname];
        case "steam":
            return ["steam", url.pathname];
        default:
            break;
    }

    const p = url.pathname.toLowerCase();
    if (p.startsWith("//totp")) return ["totp", url.pathname.slice(6)];
    if (p.startsWith("//hotp")) return ["hotp", url.pathname.slice(6)];
    if (p.startsWith("//steam")) return ["steam", url.pathname.slice(7)];

    throw new Error(`Unsupported code or unparseable path "${url.pathname}"`);
};

const parseAccount = (path: string): string | undefined => {
    let p = decodeURIComponent(path);
    if (p.startsWith("/")) p = p.slice(1);
    if (p.includes(":")) p = p.split(":").slice(1).join(":");
    return p;
};

const parseIssuer = (url: URL, path: string): string => {
    let issuer = url.searchParams.get("issuer");
    if (issuer) {
        const periodSuffixIndex = issuer.search(/&?period=\d+$/);
        if (
            periodSuffixIndex > 0 &&
            !/\s/.test(issuer.charAt(periodSuffixIndex - 1))
        ) {
            issuer = issuer.substring(0, periodSuffixIndex);
        }
        if (issuer.endsWith("period")) {
            issuer = issuer.substring(0, issuer.length - 6);
        }
        return issuer;
    }

    let p = decodeURIComponent(path);
    if (p.startsWith("/")) p = p.slice(1);
    if (p.includes(":")) p = p.split(":")[0]!;
    else if (p.includes("-")) p = p.split("-")[0]!;
    return p;
};

const parseLength = (url: URL, type: Code["type"]): number => {
    const defaultLength = type == "steam" ? 5 : 6;
    return parseInt(url.searchParams.get("digits") ?? "", 10) || defaultLength;
};

const parsePeriod = (url: URL): number =>
    parseInt(url.searchParams.get("period") ?? "", 10) || 30;

const parseAlgorithm = (url: URL): Code["algorithm"] => {
    switch (url.searchParams.get("algorithm")?.toLowerCase()) {
        case "sha256":
        case "algorithm.sha256":
            return "sha256";
        case "sha512":
        case "algorithm.sha512":
            return "sha512";
        default:
            return "sha1";
    }
};

const parseCounter = (url: URL): number | undefined => {
    const c = url.searchParams.get("counter");
    return c ? parseInt(c, 10) : undefined;
};

const parseSecret = (url: URL): string =>
    url.searchParams.get("secret")!.replaceAll(" ", "").toUpperCase();

const parseCodeDisplay = (url: URL): CodeDisplay | undefined => {
    const s = url.searchParams.get("codeDisplay");
    if (!s) return undefined;
    try {
        return CodeDisplay.parse(JSON.parse(s));
    } catch {
        return undefined;
    }
};

export const generateOTPs = (
    code: Code,
    timeOffset: number,
): { otp: string; nextOTP: string; validFor: number } => {
    const timestamp = Date.now() + timeOffset;
    const remaining = () =>
        code.period - (Math.floor(timestamp / 1000) % code.period);

    switch (code.type) {
        case "totp": {
            const totp = new TOTP({
                secret: code.secret,
                algorithm: code.algorithm,
                period: code.period,
                digits: code.length,
            });
            return {
                otp: totp.generate({ timestamp }),
                nextOTP: totp.generate({
                    timestamp: timestamp + code.period * 1000,
                }),
                validFor: remaining(),
            };
        }

        case "hotp": {
            const counter = code.counter ?? 0;
            const hotp = new HOTP({
                secret: code.secret,
                counter,
                algorithm: code.algorithm,
                digits: code.length,
            });
            return {
                otp: hotp.generate({ counter }),
                nextOTP: hotp.generate({ counter: counter + 1 }),
                validFor: Number.POSITIVE_INFINITY,
            };
        }

        case "steam": {
            const steam = new Steam({ secret: code.secret });
            return {
                otp: steam.generate({ timestamp }),
                nextOTP: steam.generate({ timestamp: timestamp + 30_000 }),
                validFor: remaining(),
            };
        }
    }
};
