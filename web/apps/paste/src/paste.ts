import { apiOrigin } from "ente-base/origins";
import { PasteClient } from "ente-paste-wasm";

// Duplicate the constant to avoid loading the entire WASM.
export const MAX_PASTE_CHARS = 4000;

const createErrorMessages: Record<string, string> = {
    empty_text: "Enter some text first",
    text_too_long: `Paste is limited to ${MAX_PASTE_CHARS} characters`,
    network: "Couldn't connect to Ente",
};

const consumeErrorMessages: Record<string, string> = {
    missing_key: "Missing key in URL",
    invalid_link: "Invalid paste link",
    invalid_access_token: "Invalid paste link",
    key_mismatch: "Invalid paste link",
    invalid_key: "Invalid key in URL",
    unavailable: "This paste has expired or was already opened",
    network: "Couldn't connect to Ente",
    request_failed: "Couldn't open paste",
    crypto: "Unable to decrypt paste",
    malformed_payload: "Unable to decrypt paste",
};

const errorMessage = (
    error: unknown,
    messages: Record<string, string>,
    fallback: string,
) => (error instanceof Error ? (messages[error.name] ?? fallback) : fallback);

let client: Promise<PasteClient> | undefined;

export const pasteClient = () =>
    (client ??= apiOrigin().then((origin) => PasteClient.init(origin)));

export const createPasteErrorMessage = (error: unknown) =>
    errorMessage(error, createErrorMessages, "Failed to create paste");

export const consumePasteErrorMessage = (error: unknown) =>
    errorMessage(error, consumeErrorMessages, "Paste is unavailable");
