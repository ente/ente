export function includes<T, U extends T>(us: readonly U[], t: T): t is U {
    const values: readonly T[] = us;
    return values.includes(t);
}
