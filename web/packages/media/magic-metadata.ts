import { decryptMetadataJSON, encryptMetadataJSON } from "ente-base/crypto";
import { nullishToZero } from "ente-utils/transform";
import { z } from "zod";

export const RemoteMagicMetadata = z.object({
    version: z.number(),
    count: z.number().nullish().transform(nullishToZero),
    data: z.string(),
    header: z.string(),
});

export interface RemoteMagicMetadata {
    version: number;
    // This is the number of non-nullish entries in the JSON object that
    // `data` encrypts.
    count: number;
    data: string;
    header: string;
}

export interface MagicMetadata<T = unknown> {
    version: number;
    count: number;
    data: T;
}

export const encryptMagicMetadata = async (
    magicMetadata: MagicMetadata,
    key: string,
): Promise<RemoteMagicMetadata> => {
    const { version } = magicMetadata;

    const newMM = createMagicMetadata(magicMetadata.data);
    const { count } = newMM;

    const { encryptedData: data, decryptionHeader: header } =
        await encryptMetadataJSON(newMM.data, key);

    return { version, count, data, header };
};

export const createMagicMetadata = (data: unknown, version?: number) => {
    // Remote rejects metadata updates whose entry count decreases, so nullish
    // entries are trimmed instead of being sent. A consequence is that an
    // entry cannot be deleted by setting it to null; reset it to its empty
    // primitive (e.g. 0) instead.
    const jsonObject = Object.fromEntries(
        Object.entries(data ?? {}).filter(
            ([, v]) => v !== null && v !== undefined,
        ),
    );

    const count = Object.keys(jsonObject).length;

    return { version: version ?? 1, count, data: jsonObject };
};

export const decryptMagicMetadata = async (
    remoteMagicMetadata: RemoteMagicMetadata,
    key: string,
): Promise<MagicMetadata> => {
    const {
        version,
        count,
        data: encryptedData,
        header: decryptionHeader,
    } = remoteMagicMetadata;

    const data = await decryptMetadataJSON(
        { encryptedData, decryptionHeader },
        key,
    );

    return { version, count, data };
};
