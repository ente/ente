export const groupSpaceActivities = <T>(
    items: T[],
    activity: (item: T) => { createdAtMs: number; isNew: boolean },
) => {
    const today = new Date();
    const startOfTodayMs = new Date(
        today.getFullYear(),
        today.getMonth(),
        today.getDate(),
    ).getTime();
    const startOfYesterdayMs = new Date(
        today.getFullYear(),
        today.getMonth(),
        today.getDate() - 1,
    ).getTime();
    const startOfLast7DaysMs = new Date(
        today.getFullYear(),
        today.getMonth(),
        today.getDate() - 7,
    ).getTime();
    const sections: { title: string; items: T[] }[] = [
        { title: "New", items: [] },
        { title: "Today", items: [] },
        { title: "Yesterday", items: [] },
        { title: "Last 7 days", items: [] },
        { title: "Earlier", items: [] },
    ];
    for (const item of items) {
        const { createdAtMs, isNew } = activity(item);
        const index = isNew
            ? 0
            : createdAtMs >= startOfTodayMs
              ? 1
              : createdAtMs >= startOfYesterdayMs
                ? 2
                : createdAtMs >= startOfLast7DaysMs
                  ? 3
                  : 4;
        sections[index]!.items.push(item);
    }
    return sections;
};
