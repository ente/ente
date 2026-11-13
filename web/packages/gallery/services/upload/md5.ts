// RFC 1321 MD5, returning the checksum as base64.

const shifts = new Uint8Array([
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5,
    9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11,
    16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10,
    15, 21,
]);

const constants = (() => {
    const k = new Uint32Array(64);
    for (let i = 0; i < 64; i++) {
        k[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 2 ** 32);
    }
    return k;
})();

const leftRotate = (value: number, amount: number) =>
    (value << amount) | (value >>> (32 - amount));

const toUint8ArrayLE = (word: number) => {
    const bytes = new Uint8Array(4);
    bytes[0] = word & 0xff;
    bytes[1] = (word >>> 8) & 0xff;
    bytes[2] = (word >>> 16) & 0xff;
    bytes[3] = (word >>> 24) & 0xff;
    return bytes;
};

const bytesToBase64 = (bytes: Uint8Array) => {
    if (typeof Buffer != "undefined") {
        return Buffer.from(bytes).toString("base64");
    }
    let binary = "";
    for (const byte of bytes) {
        binary += String.fromCharCode(byte);
    }
    return btoa(binary);
};

export const computeMd5Base64 = (data: Uint8Array): string => {
    const originalLengthBits = data.length * 8;
    // Round MD5's padded input to 64-byte blocks, measured in 32-bit words.
    const paddedLength = (((data.length + 8) >>> 6) << 4) + 16;
    const words = new Uint32Array(paddedLength);

    for (const [i, value] of data.entries()) {
        const wordIndex = i >> 2;
        const existing = words[wordIndex] ?? 0;
        words[wordIndex] = existing | (value << ((i % 4) * 8));
    }

    const paddingIndex = data.length >> 2;
    const paddingExisting = words[paddingIndex] ?? 0;
    words[paddingIndex] = paddingExisting | (0x80 << ((data.length % 4) * 8));
    words[paddedLength - 2] = originalLengthBits & 0xffffffff;
    words[paddedLength - 1] = (originalLengthBits / 0x100000000) | 0;

    let a = 0x67452301;
    let b = 0xefcdab89;
    let c = 0x98badcfe;
    let d = 0x10325476;

    for (let i = 0; i < words.length; i += 16) {
        let A = a;
        let B = b;
        let C = c;
        let D = d;

        for (let j = 0; j < 64; j++) {
            let f: number;
            let g: number;

            if (j < 16) {
                f = (B & C) | (~B & D);
                g = j;
            } else if (j < 32) {
                f = (D & B) | (~D & C);
                g = (5 * j + 1) % 16;
            } else if (j < 48) {
                f = B ^ C ^ D;
                g = (3 * j + 5) % 16;
            } else {
                f = C ^ (B | ~D);
                g = (7 * j) % 16;
            }

            const temp = D;
            D = C;
            C = B;
            const word = words[i + g] ?? 0;
            const constant = constants[j] ?? 0;
            const shift = shifts[j] ?? 0;
            const sum = (A + f + constant + word) >>> 0;
            B = (B + leftRotate(sum, shift)) >>> 0;
            A = temp;
        }

        a = (a + A) >>> 0;
        b = (b + B) >>> 0;
        c = (c + C) >>> 0;
        d = (d + D) >>> 0;
    }

    const digest = new Uint8Array(16);
    digest.set(toUint8ArrayLE(a), 0);
    digest.set(toUint8ArrayLE(b), 4);
    digest.set(toUint8ArrayLE(c), 8);
    digest.set(toUint8ArrayLE(d), 12);

    return bytesToBase64(digest);
};
