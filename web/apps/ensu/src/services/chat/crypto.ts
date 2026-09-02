import { isTauriRuntime } from "@/services/tauri-runtime";
import * as wasmCrypto from "ente-ensu-wasm";

type TauriCoreModule = typeof import("@tauri-apps/api/core");

export interface EncryptedChatPayload {
    encryptedData: string;
    header: string;
}

const tauriInvoke = async <T>(
    ...args: Parameters<TauriCoreModule["invoke"]>
) => {
    const { invoke } = await import("@tauri-apps/api/core");
    return invoke<T>(...args);
};

const invokeAttachmentCommand = async (
    command: string,
    data: Uint8Array,
    chatKeyB64: string,
    sessionUuid: string,
) =>
    new Uint8Array(
        await tauriInvoke<ArrayBuffer>(command, data, {
            headers: { "chat-key": chatKeyB64, "session-uuid": sessionUuid },
        }),
    );

export const generateChatKey = async () =>
    isTauriRuntime()
        ? tauriInvoke<string>("chat_crypto_generate_key")
        : wasmCrypto.generateChatKey();

export const encryptChatPayload = async (
    payload: unknown,
    chatKeyB64: string,
): Promise<EncryptedChatPayload> => {
    const value = JSON.stringify(payload);
    if (isTauriRuntime()) {
        return tauriInvoke("chat_crypto_encrypt_payload", {
            input: { value, keyB64: chatKeyB64 },
        });
    }
    return wasmCrypto.encryptChatPayload(value, chatKeyB64);
};

export const decryptChatPayload = async (
    { encryptedData, header }: EncryptedChatPayload,
    chatKeyB64: string,
): Promise<unknown> => {
    const value = isTauriRuntime()
        ? await tauriInvoke<string>("chat_crypto_decrypt_payload", {
              input: {
                  encryptedDataB64: encryptedData,
                  headerB64: header,
                  keyB64: chatKeyB64,
              },
          })
        : await wasmCrypto.decryptChatPayload(
              encryptedData,
              header,
              chatKeyB64,
          );
    return JSON.parse(value);
};

export const encryptChatField = async (
    value: string,
    chatKeyB64: string,
): Promise<string> =>
    isTauriRuntime()
        ? tauriInvoke("chat_crypto_encrypt_field", {
              input: { value, keyB64: chatKeyB64 },
          })
        : wasmCrypto.encryptChatField(value, chatKeyB64);

export const decryptChatField = async (
    value: string,
    chatKeyB64: string,
): Promise<string> =>
    isTauriRuntime()
        ? tauriInvoke("chat_crypto_decrypt_field", {
              input: { value, keyB64: chatKeyB64 },
          })
        : wasmCrypto.decryptChatField(value, chatKeyB64);

export const encryptAttachmentBytes = async (
    data: Uint8Array,
    chatKeyB64: string,
    sessionUuid: string,
): Promise<Uint8Array> =>
    isTauriRuntime()
        ? invokeAttachmentCommand(
              "chat_crypto_encrypt_attachment",
              data,
              chatKeyB64,
              sessionUuid,
          )
        : wasmCrypto.encryptChatAttachment(data, chatKeyB64, sessionUuid);

export const decryptAttachmentBytes = async (
    data: Uint8Array,
    chatKeyB64: string,
    sessionUuid: string,
): Promise<Uint8Array> =>
    isTauriRuntime()
        ? invokeAttachmentCommand(
              "chat_crypto_decrypt_attachment",
              data,
              chatKeyB64,
              sessionUuid,
          )
        : wasmCrypto.decryptChatAttachment(data, chatKeyB64, sessionUuid);
