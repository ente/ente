export class SpaceMediaRateLimitError extends Error {
    readonly retryAt = Date.now() + 60_000;

    constructor(cause: unknown) {
        super("Couldn't load media. Please try again later.", { cause });
    }
}

let rateLimitError: SpaceMediaRateLimitError | undefined;

export const clearSpaceMediaLoadCooldown = () => {
    rateLimitError = undefined;
};

export const loadSpaceMedia = async <T>(load: () => Promise<T>): Promise<T> => {
    if (rateLimitError && Date.now() < rateLimitError.retryAt)
        throw rateLimitError;

    try {
        return await load();
    } catch (error) {
        if (
            typeof error == "object" &&
            error !== null &&
            "status" in error &&
            error.status == 429
        ) {
            rateLimitError = new SpaceMediaRateLimitError(error);
            throw rateLimitError;
        }
        throw error;
    }
};
