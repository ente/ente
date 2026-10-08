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
    const mondayDate = today.getDate() - ((today.getDay() + 6) % 7);
    const startOfThisWeekMs = new Date(
        today.getFullYear(),
        today.getMonth(),
        mondayDate,
    ).getTime();
    const startOfLastWeekMs = new Date(
        today.getFullYear(),
        today.getMonth(),
        mondayDate - 7,
    ).getTime();
    const startOfThisMonthMs = new Date(
        today.getFullYear(),
        today.getMonth(),
        1,
    ).getTime();
    const sections: { title: string; items: T[] }[] = [
        { title: "New", items: [] },
        { title: "Today", items: [] },
        { title: "Yesterday", items: [] },
        { title: "This week", items: [] },
        { title: "Last week", items: [] },
        { title: "This month", items: [] },
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
                : createdAtMs >= startOfThisWeekMs
                  ? 3
                  : createdAtMs >= startOfLastWeekMs
                    ? 4
                    : createdAtMs >= startOfThisMonthMs
                      ? 5
                      : 6;
        sections[index]!.items.push(item);
    }
    return sections;
};
