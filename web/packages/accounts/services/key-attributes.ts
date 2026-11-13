import { generateInteractiveKeyAttributes as generate } from "./crypto";
import { RemoteKeyAttributes, type KeyAttributes } from "./user";

export const generateInteractiveKeyAttributes = async (
    password: string,
    keyAttributes: KeyAttributes,
    masterKey: string,
): Promise<KeyAttributes> =>
    RemoteKeyAttributes.parse(
        await generate(password, keyAttributes, masterKey),
    );
