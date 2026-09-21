import type {
    EncryptedBox,
    OpenAccountSpaceCtxInput,
    OpenSpaceLinkCtxInput,
    SpaceAccountCtxHandle,
    SpaceLinkCtxHandle,
} from "./pkg/ente_space_wasm";

export type {
    DecryptedSpaceProfile,
    MessageConversationActivity,
    MessageResponse,
    PostObjectPayload,
    PostPage,
    PostResponse,
    ProfileAvatarResponse,
    SpaceAccountCtxHandle,
    SpaceActorResponse,
    SpaceKeyResponse,
    SpaceLinkCtxHandle,
    UpdateSpaceProfileResponse,
} from "./pkg/ente_space_wasm";

const wasm = () => import("./pkg/ente_space_wasm");

export const generateKey = async () => (await wasm()).cryptoGenerateKey();

export const encryptBox = async (dataB64: string, keyB64: string) =>
    (await wasm()).cryptoEncryptBox(dataB64, keyB64);

export const decryptBox = async (box: EncryptedBox, keyB64: string) =>
    (await wasm()).cryptoDecryptBox(box.encryptedData, box.nonce, keyB64);

export const openSpaceAccountContext = async (
    input: OpenAccountSpaceCtxInput,
): Promise<SpaceAccountCtxHandle> => (await wasm()).spaceOpenAccountCtx(input);

export const openSpaceLinkContext = async (
    input: OpenSpaceLinkCtxInput,
): Promise<SpaceLinkCtxHandle> => (await wasm()).spaceOpenLinkCtx(input);
