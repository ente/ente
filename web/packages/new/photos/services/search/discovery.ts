/** Rank only candidates counted against the worker's searchable library. */
export const searchDiscoveryLabels = (
    candidates: {
        type: "collection" | "location";
        label: string;
        fileCount: number;
    }[],
) => {
    const seen = new Set<string>();
    const labels: string[] = [];
    for (const [type, limit] of [
        ["collection", 2],
        ["location", 1],
    ] as const) {
        let count = 0;
        for (const candidate of candidates
            .filter((c) => c.type === type && c.fileCount > 0 && c.label.trim())
            .sort(
                (a, b) =>
                    b.fileCount - a.fileCount || a.label.localeCompare(b.label),
            )) {
            const key = candidate.label.trim().toLocaleLowerCase();
            if (seen.has(key)) continue;
            seen.add(key);
            labels.push(candidate.label);
            if (++count === limit) break;
        }
    }
    return labels;
};
