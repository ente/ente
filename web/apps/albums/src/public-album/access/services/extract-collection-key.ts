import bs58 from "bs58";
import { fromHex, toB64 } from "ente-base/crypto";

export const extractCollectionKeyFromShareURL = async (url: URL) => {
    const ck = url.hash.slice(1);
    // Legacy links use hex; current links use base58.
    return ck.length < 50 ? await toB64(bs58.decode(ck)) : await fromHex(ck);
};
