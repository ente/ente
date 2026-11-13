export const wait = (ms: number) =>
    new Promise((resolve) => setTimeout(resolve, ms));

export const nullToUndefined = <T>(v: T | null | undefined): T | undefined =>
    v === null ? undefined : v;
