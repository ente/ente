// Heuristics to match an authenticator item (issuer/account) to the site the
// user is visiting, so we can suggest the right code.
import type { Code } from "./ente/code";

const normalize = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, "");

const generics = new Set([
    "www",
    "com",
    "net",
    "org",
    "io",
    "co",
    "app",
    "dev",
    "login",
    "account",
    "accounts",
    "auth",
    "signin",
    "my",
    "id",
]);

export const scoreCodeForHost = (code: Code, host: string): number => {
    const issuer = normalize(code.issuer ?? "");
    const account = normalize(code.account ?? "");
    const hostN = normalize(host);
    if (!hostN) return 0;

    const labels = host
        .toLowerCase()
        .split(".")
        .map(normalize)
        .filter((l) => l.length >= 3 && !generics.has(l));

    let score = 0;

    if (issuer.length >= 3) {
        if (issuer === hostN) score = Math.max(score, 120);
        else if (hostN.includes(issuer) || issuer.includes(hostN))
            score = Math.max(score, 90);
    }

    for (const label of labels) {
        if (issuer === label) score = Math.max(score, 100);
        else if (issuer && (issuer.includes(label) || label.includes(issuer)))
            score = Math.max(score, 75);
        if (issuer.length < 3 && account && account.includes(label))
            score = Math.max(score, 50);
    }

    return score;
};

export const findBestCodeForHost = (
    codes: Code[],
    host: string,
): Code | undefined => {
    let best: Code | undefined;
    let bestScore = 0;
    for (const code of codes) {
        const score = scoreCodeForHost(code, host);
        if (score > bestScore) {
            best = code;
            bestScore = score;
        }
    }
    return best;
};
