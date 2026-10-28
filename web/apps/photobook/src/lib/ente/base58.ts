// Minimal base58 (Bitcoin alphabet) decoder. Ente public album URL fragments
// use this encoding for short collection keys; longer ones use hex. Ente web
// uses the `bs58` npm package — we inline a tiny decoder to avoid the dep.

const ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
const MAP: Record<string, number | undefined> = {};
for (let i = 0; i < ALPHABET.length; i++) MAP[ALPHABET[i]!] = i;

export function base58Decode(s: string): Uint8Array {
    if (!s) return new Uint8Array();

    // Leading '1' characters map to leading zero bytes.
    let zeros = 0;
    while (zeros < s.length && s[zeros] === "1") zeros++;

    const size = s.length;
    const b256 = new Uint8Array(size);
    let length = 0;

    for (let i = zeros; i < s.length; i++) {
        const ch = s[i]!;
        const digit = MAP[ch];
        if (digit === undefined) {
            throw new Error(`Invalid base58 character: ${ch}`);
        }
        let carry = digit;
        let j = 0;
        for (
            let k = size - 1;
            (carry !== 0 || j < length) && k >= 0;
            k--, j++
        ) {
            carry += 58 * b256[k]!;
            b256[k] = carry % 256;
            carry = Math.floor(carry / 256);
        }
        length = j;
    }

    const start = size - length;
    const result = new Uint8Array(zeros + length);
    for (let i = 0; i < length; i++) result[zeros + i] = b256[start + i]!;
    return result;
}
