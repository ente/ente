import { afterEach, expect, test, vi } from "vitest";
import { groupSpaceActivities } from "../src/utils/activity-sections";

afterEach(() => vi.useRealTimers());

test("new activity takes priority and history follows local calendar boundaries", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(2026, 9, 21, 12));
    const items = [
        {
            id: "old-unread",
            createdAtMs: new Date(2026, 7, 1).getTime(),
            isNew: true,
        },
        {
            id: "today",
            createdAtMs: new Date(2026, 9, 21).getTime(),
            isNew: false,
        },
        {
            id: "yesterday",
            createdAtMs: new Date(2026, 9, 20).getTime(),
            isNew: false,
        },
        {
            id: "this-week",
            createdAtMs: new Date(2026, 9, 19).getTime(),
            isNew: false,
        },
        {
            id: "last-week",
            createdAtMs: new Date(2026, 9, 12).getTime(),
            isNew: false,
        },
        {
            id: "this-month",
            createdAtMs: new Date(2026, 9, 1).getTime(),
            isNew: false,
        },
        {
            id: "earlier",
            createdAtMs: new Date(2026, 8, 30, 23, 59).getTime(),
            isNew: false,
        },
    ];
    expect(
        groupSpaceActivities(items, (item) => item).map((section) => ({
            title: section.title,
            ids: section.items.map((item) => item.id),
        })),
    ).toEqual([
        { title: "New", ids: ["old-unread"] },
        { title: "Today", ids: ["today"] },
        { title: "Yesterday", ids: ["yesterday"] },
        { title: "This week", ids: ["this-week"] },
        { title: "Last week", ids: ["last-week"] },
        { title: "This month", ids: ["this-month"] },
        { title: "Earlier", ids: ["earlier"] },
    ]);
});

test.each([
    {
        name: "Sunday stays in the current week",
        now: new Date(2026, 9, 25, 12),
        dates: [new Date(2026, 9, 19), new Date(2026, 9, 18, 23, 59)],
        titles: ["This week", "Last week"],
    },
    {
        name: "yesterday takes priority when Monday crosses a year boundary",
        now: new Date(2027, 0, 4, 12),
        dates: [
            new Date(2027, 0, 3),
            new Date(2027, 0, 1),
            new Date(2026, 11, 28),
            new Date(2026, 11, 27, 23, 59),
        ],
        titles: ["Yesterday", "Last week", "Last week", "Earlier"],
    },
    {
        name: "calendar weeks span month and daylight-saving boundaries",
        now: new Date(2026, 10, 4, 12),
        dates: [
            new Date(2026, 10, 2),
            new Date(2026, 10, 1),
            new Date(2026, 9, 26),
            new Date(2026, 9, 25, 23, 59),
        ],
        titles: ["This week", "Last week", "Last week", "Earlier"],
    },
])("$name", ({ now, dates, titles }) => {
    vi.useFakeTimers();
    vi.setSystemTime(now);
    const sections = groupSpaceActivities(dates, (date) => ({
        createdAtMs: date.getTime(),
        isNew: false,
    }));
    expect(
        dates.map(
            (date) =>
                sections.find((section) => section.items.includes(date))?.title,
        ),
    ).toEqual(titles);
});
