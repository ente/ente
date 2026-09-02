const wasm = () => import("./pkg/ente_space_wasm");

export type SpaceAccountCtxHandle =
    import("./pkg/ente_space_wasm").SpaceAccountCtxHandle;
export type SpaceLinkCtxHandle =
    import("./pkg/ente_space_wasm").SpaceLinkCtxHandle;

export interface OpenSpaceAccountContextInput {
    baseUrl: string;
    clientPackage: string;
    clientVersion?: string;
    ownedSpaces?: unknown[];
    spaceRootKeyB64: string;
    spaceSessionToken: string;
}

export interface OpenSpaceLinkContextInput {
    accessKey: string;
    baseUrl: string;
    clientPackage: string;
    clientVersion?: string;
    spaceUsername: string;
}

export const encryptSpaceRootEntityKey = async (
    spaceRootKeyB64: string,
    masterKeyB64: string,
) => (await wasm()).encryptSpaceRootEntityKey(spaceRootKeyB64, masterKeyB64);

export const decryptSpaceRootEntityKey = async (
    encryptedKeyB64: string,
    masterKeyB64: string,
) => (await wasm()).decryptSpaceRootEntityKey(encryptedKeyB64, masterKeyB64);

export const openSpaceAccountContext = async (
    input: OpenSpaceAccountContextInput,
): Promise<SpaceAccountCtxHandle> => (await wasm()).spaceOpenAccountCtx(input);

export const openSpaceLinkContext = async (
    input: OpenSpaceLinkContextInput,
): Promise<SpaceLinkCtxHandle> => (await wasm()).spaceOpenLinkCtx(input);
