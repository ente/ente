/**
 * @file Typed key material and related fixed-size values.
 */

const sized = (bytes: Uint8Array, length: number, name: string): Uint8Array => {
    if (bytes.length !== length) {
        throw new Error(
            `${name} must be ${length} bytes, but got ${bytes.length}`,
        );
    }
    return bytes;
};

/** A 256-bit symmetric encryption key. */
export class Key {
    private constructor(private readonly _bytes: Uint8Array) {}

    /**
     * Construct a key from `bytes`, validating the length.
     *
     * Throws unless `bytes` is exactly 32 bytes long.
     */
    static fromBytes(bytes: Uint8Array): Key {
        return new Key(sized(bytes, 32, "Key"));
    }

    /** The raw key bytes. */
    get bytes(): Uint8Array {
        return this._bytes;
    }
}

/** A 192-bit SecretBox nonce. Not secret. */
export class Nonce {
    private constructor(private readonly _bytes: Uint8Array) {}

    /**
     * Construct a nonce from `bytes`, validating the length.
     *
     * Throws unless `bytes` is exactly 24 bytes long.
     */
    static fromBytes(bytes: Uint8Array): Nonce {
        return new Nonce(sized(bytes, 24, "Nonce"));
    }

    /** The raw nonce bytes. */
    get bytes(): Uint8Array {
        return this._bytes;
    }
}

/** A 128-bit key derivation salt. Not secret. */
export class Salt {
    private constructor(private readonly _bytes: Uint8Array) {}

    /**
     * Construct a salt from `bytes`, validating the length.
     *
     * Throws unless `bytes` is exactly 16 bytes long.
     */
    static fromBytes(bytes: Uint8Array): Salt {
        return new Salt(sized(bytes, 16, "Salt"));
    }

    /** The raw salt bytes. */
    get bytes(): Uint8Array {
        return this._bytes;
    }
}

/** A 192-bit SecretStream decryption header. Not secret. */
export class Header {
    private constructor(private readonly _bytes: Uint8Array) {}

    /**
     * Construct a header from `bytes`, validating the length.
     *
     * Throws unless `bytes` is exactly 24 bytes long.
     */
    static fromBytes(bytes: Uint8Array): Header {
        return new Header(sized(bytes, 24, "Header"));
    }

    /** The raw header bytes. */
    get bytes(): Uint8Array {
        return this._bytes;
    }
}

/** An X25519 public key. Not secret. */
export class PublicKey {
    private constructor(private readonly _bytes: Uint8Array) {}

    /**
     * Construct a public key from `bytes`, validating the length.
     *
     * Throws unless `bytes` is exactly 32 bytes long.
     */
    static fromBytes(bytes: Uint8Array): PublicKey {
        return new PublicKey(sized(bytes, 32, "PublicKey"));
    }

    /** The raw public key bytes. */
    get bytes(): Uint8Array {
        return this._bytes;
    }
}

/** An X25519 secret key. */
export class SecretKey {
    private constructor(private readonly _bytes: Uint8Array) {}

    /**
     * Construct a secret key from `bytes`, validating the length.
     *
     * Throws unless `bytes` is exactly 32 bytes long.
     */
    static fromBytes(bytes: Uint8Array): SecretKey {
        return new SecretKey(sized(bytes, 32, "SecretKey"));
    }

    /** The raw secret key bytes. */
    get bytes(): Uint8Array {
        return this._bytes;
    }
}
