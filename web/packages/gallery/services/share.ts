import bs58 from "bs58";
import { fromB64, fromHex, toB64 } from "ente-base/crypto";

export const appendCollectionKeyToShareURL = async (
    url: string,
    collectionKey: string,
) => {
    const sharableURL = new URL(url);

    const bytes = await fromB64(collectionKey);
    sharableURL.hash = bs58.encode(bytes);
    return sharableURL.href;
};

export const extractCollectionKeyFromShareURL = async (url: URL) => {
    const ck = url.hash.slice(1);
    return ck.length < 50 ? await toB64(bs58.decode(ck)) : await fromHex(ck);
};
