const OVERFLOW_SAFETY_TOKENS = 256;
export const DEFAULT_WEB_CONTEXT_SIZE = 4096;
export const DEFAULT_TAURI_CONTEXT_SIZE = 12000;
const MAX_CONTEXT_SIZE = 2_147_483_647;

export function resolveGenerationBudget(
    contextSize: number,
    configuredMaxTokens?: number,
) {
    if (
        !Number.isSafeInteger(contextSize) ||
        contextSize <= OVERFLOW_SAFETY_TOKENS + 1 ||
        contextSize > MAX_CONTEXT_SIZE
    ) {
        throw new Error(
            "Context length must be a whole number greater than 257.",
        );
    }
    const maxTokens =
        configuredMaxTokens ?? Math.min(2048, Math.floor(contextSize / 4));
    if (!Number.isSafeInteger(maxTokens) || maxTokens <= 0) {
        throw new Error("The response budget must be a positive whole number.");
    }
    const inputBudget = contextSize - maxTokens - OVERFLOW_SAFETY_TOKENS;
    if (inputBudget <= 0) {
        throw new Error(
            `The ${contextSize}-token context cannot fit the conversation and response. Increase context length.`,
        );
    }
    return { contextSize, maxTokens, inputBudget };
}
