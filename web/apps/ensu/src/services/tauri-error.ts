export interface TauriCommandError {
    name?: string;
    message?: string;
}

export const tauriCommandError = (error: unknown): TauriCommandError => {
    if (!error || typeof error !== "object") return {};
    const record = error as Record<string, unknown>;
    return {
        name: typeof record.name === "string" ? record.name : undefined,
        message:
            typeof record.message === "string" ? record.message : undefined,
    };
};
