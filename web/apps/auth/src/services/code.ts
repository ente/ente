import log from "ente-base/log";
import { nullToUndefined } from "ente-utils/transform";
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
    trashed: z.boolean().nullish().transform(nullToUndefined),
    pinned: z.boolean().nullish().transform(nullToUndefined),
    note: z.string().nullish().transform(nullToUndefined),
});

export const codeFromURIString = (id: string, uriString: string): Code => {
    try {
        return _codeFromURIString(id, uriString);
    } catch (e) {
        // Account names in legacy encodings can contain a raw "#", which makes
        // the URL parser treat the rest of the URI as a fragment. Retry with
        // the "#" escaped.
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
    // Browsers parse URLs with a non-http(s) scheme like otpauth differently:
    // for "otpauth://hotp/Test", Safari puts "hotp" in the host and "/Test" in
    // the pathname, while Chrome and Firefox leave the host empty and put
    // "//hotp/Test" in the pathname. Handle both.

    switch (url.host.toLowerCase()) {
        case "totp":
            return ["totp", url.pathname.toLowerCase()];
        case "hotp":
            return ["hotp", url.pathname.toLowerCase()];
        case "steam":
            return ["steam", url.pathname.toLowerCase()];
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
        // Old versions of the Ente Auth app had a bug that could append the
        // period query param to the issuer; strip such suffixes.
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

// The otpauth URI query param is "digits", but Steam codes are 5 non-digit
// characters, so we use a neutral "length" and a type-specific default.
const parseLength = (url: URL, type: Code["type"]): number => {
    const defaultLength = type == "steam" ? 5 : 6;
    return parseInt(url.searchParams.get("digits") ?? "", 10) || defaultLength;
};

const parsePeriod = (url: URL): number =>
    parseInt(url.searchParams.get("period") ?? "", 10) || 30;

const parseAlgorithm = (url: URL): Code["algorithm"] => {
    switch (url.searchParams.get("algorithm")?.toLowerCase()) {
        case "sha256":
            return "sha256";
        case "sha512":
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
    } catch (e) {
        log.error(`Ignoring unparseable code display ${s}`, e);
        return undefined;
    }
};

export const generateOTPs = (
    code: Code,
    timeOffset: number,
): [otp: string, nextOTP: string] => {
    let otp: string;
    let nextOTP: string;
    const timestamp = Date.now() + timeOffset;
    switch (code.type) {
        case "totp": {
            const totp = new TOTP({
                secret: code.secret,
                algorithm: code.algorithm,
                period: code.period,
                digits: code.length,
            });
            otp = totp.generate({ timestamp });
            nextOTP = totp.generate({
                timestamp: timestamp + code.period * 1000,
            });
            break;
        }

        case "hotp": {
            const counter = code.counter ?? 0;
            const hotp = new HOTP({
                secret: code.secret,
                counter: counter,
                algorithm: code.algorithm,
            });
            otp = hotp.generate({ counter });
            nextOTP = hotp.generate({ counter: counter + 1 });
            break;
        }

        case "steam": {
            const steam = new Steam({ secret: code.secret });
            otp = steam.generate({ timestamp });
            nextOTP = steam.generate({
                timestamp: timestamp + code.period * 1000,
            });
            break;
        }
    }
    return [otp, nextOTP];
};
