export const nullToUndefined = <T>(v: T | null | undefined): T | undefined =>
    v === null ? undefined : v;

export const nullishToFalse = (v: boolean | null | undefined): boolean =>
    v ?? false;

export const nullishToZero = (v: number | null | undefined): number => v ?? 0;

export const nullishToBlank = (v: string | null | undefined): string => v ?? "";

export const nullishToEmpty = <T>(v: T[] | null | undefined): T[] => v ?? [];
