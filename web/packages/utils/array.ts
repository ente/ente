export const shuffled = <T>(xs: T[]): T[] =>
    xs
        .map((x) => [Math.random(), x])
        .sort()
        .map(([, x]) => x) as T[];

export const randomSample = <T>(items: T[], n: number) => {
    if (items.length <= n) return shuffled(items);
    if (n == 0) return [];

    if (n > items.length / 3) {
        // Sampling distinct random indexes degenerates into a long retry loop
        // when n is a large fraction of the items, so shuffle instead.
        return shuffled(items).slice(0, n);
    }

    const ix = new Set<number>();
    while (ix.size < n) {
        ix.add(Math.floor(Math.random() * items.length));
    }
    return [...ix].map((i) => items[i]!);
};

// The `a ?? b` idiom does not treat the empty string as absent, so it cannot
// replace this helper.
export const firstNonEmpty = (
    ss: (string | undefined)[],
): string | undefined => {
    for (const s of ss) if (s && s.length > 0) return s;
    return undefined;
};

export const mergeUint8Arrays = (as: Uint8Array[]): Uint8Array<ArrayBuffer> => {
    const len = as.reduce((len, xs) => len + xs.length, 0);
    const result = new Uint8Array(len);
    as.reduce((n, xs) => (result.set(xs, n), n + xs.length), 0);
    return result;
};

export const batch = <T>(xs: T[], batchSize: number): T[][] => {
    const batches: T[][] = [];
    for (let i = 0; i < xs.length; i += batchSize) {
        batches.push(xs.slice(i, i + batchSize));
    }
    return batches;
};

export const splitByPredicate = <T>(
    xs: T[],
    predicate: (t: T) => boolean,
): [T[], T[]] =>
    xs.reduce<[T[], T[]]>(
        (result, x) => {
            (predicate(x) ? result[0] : result[1]).push(x);
            return result;
        },
        [[], []],
    );
