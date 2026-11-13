export const ensurePrecondition = (v: unknown): void => {
    if (!v) throw new Error("Precondition failed");
};

export const ensure = <T>(v: T | null | undefined): T => {
    if (v === null) throw new Error("Required value was null");
    if (v === undefined) throw new Error("Required value was undefined");
    return v;
};

export const ensureString = (v: unknown): string => {
    if (typeof v != "string")
        throw new Error(`Expected a string, instead found ${String(v)}`);
    return v;
};

export const ensureNumber = (v: unknown): number => {
    if (typeof v != "number" || Number.isNaN(v))
        throw new Error(`Expected a number, instead found ${String(v)}`);
    return v;
};

export const ensureInteger = (v: unknown): number => {
    if (typeof v != "number")
        throw new Error(`Expected a number, instead found ${String(v)}`);
    if (!Number.isInteger(v))
        throw new Error(`Expected an integer, instead found ${v}`);
    return v;
};
