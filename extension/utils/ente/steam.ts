// Copied from `web/apps/auth/src/services/steam.ts` (MIT reference inside).
import { hmac } from "@noble/hashes/hmac.js";
import { sha1 } from "@noble/hashes/legacy.js";
import { Secret } from "otpauth";

export class Steam {
    secret: Secret;
    period: number;

    constructor({ secret }: { secret: string }) {
        this.secret = Secret.fromBase32(secret);
        this.period = 30;
    }

    generate({ timestamp }: { timestamp: number } = { timestamp: Date.now() }) {
        const counter = Math.floor(timestamp / 1000 / this.period);
        const digest = hmac(sha1, this.secret.bytes, uintToArray(counter));

        const offset = digest[digest.length - 1]! & 15;
        let otp =
            ((digest[offset]! & 127) << 24) |
            ((digest[offset + 1]! & 255) << 16) |
            ((digest[offset + 2]! & 255) << 8) |
            (digest[offset + 3]! & 255);

        const alphabet = "23456789BCDFGHJKMNPQRTVWXY";
        const N = alphabet.length;
        const steamOTP = [];
        for (let i = 0; i < 5; i++) {
            steamOTP.push(alphabet[otp % N]);
            otp = Math.trunc(otp / N);
        }
        return steamOTP.join("");
    }
}

const uintToArray = (n: number): Uint8Array => {
    const result = new Uint8Array(8);
    for (let i = 7; i >= 0; i--) {
        result[i] = n & 255;
        n >>= 8;
    }
    return result;
};
