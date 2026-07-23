import { hmac } from "@noble/hashes/hmac.js";
import { sha1 } from "@noble/hashes/legacy.js";
import { Secret } from "otpauth";

/**
 * Steam OTPs.
 *
 * Steam's algorithm is a custom variant of TOTP that uses a 26-character
 * alphabet instead of digits.
 *
 * A Dart implementation of the algorithm can be found in
 * https://github.com/elliotwutingfeng/steam_totp/blob/main/lib/src/steam_totp_base.dart
 * (MIT license), and we use that as a reference. Our implementation is written
 * in the style of the other TOTP/HOTP classes that are provided by the otpauth
 * JS library that we use for the normal TOTP/HOTP generation
 * https://github.com/hectorm/otpauth/blob/master/src/hotp.js (MIT license).
 */
export class Steam {
    secret: Secret;
    period: number;

    constructor({ secret }: { secret: string }) {
        this.secret = Secret.fromBase32(secret);
        this.period = 30;
    }

    generate({ timestamp }: { timestamp: number } = { timestamp: Date.now() }) {
        // Same as regular TOTP.
        const counter = Math.floor(timestamp / 1000 / this.period);

        // Same as regular HOTP, but algorithm is fixed to SHA-1.
        const digest = hmac(sha1, this.secret.bytes, uintToArray(counter));

        // Same calculation as regular HOTP.
        const offset = digest[digest.length - 1]! & 15;
        let otp =
            ((digest[offset]! & 127) << 24) |
            ((digest[offset + 1]! & 255) << 16) |
            ((digest[offset + 2]! & 255) << 8) |
            (digest[offset + 3]! & 255);

        // However, instead of using this as the OTP, use it to index into
        // the steam OTP alphabet.
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

// Equivalent to
// https://github.com/hectorm/otpauth/blob/master/src/utils/encoding/uint.js
const uintToArray = (n: number): Uint8Array => {
    const result = new Uint8Array(8);
    for (let i = 7; i >= 0; i--) {
        result[i] = n & 255;
        n >>= 8;
    }
    return result;
};
