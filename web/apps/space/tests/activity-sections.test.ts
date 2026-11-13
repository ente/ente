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
            id: "two-days-ago",
            createdAtMs: new Date(2026, 9, 19).getTime(),
            isNew: false,
        },
        {
            id: "seven-days-ago",
            createdAtMs: new Date(2026, 9, 14).getTime(),
            isNew: false,
        },
        {
            id: "before-seven-days",
            createdAtMs: new Date(2026, 9, 13, 23, 59, 59, 999).getTime(),
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
        { title: "Last 7 days", ids: ["two-days-ago", "seven-days-ago"] },
        { title: "Earlier", ids: ["before-seven-days", "earlier"] },
    ]);
});

test.each([
    {
        name: "seven-day range crosses calendar weeks",
        now: new Date(2026, 9, 25, 12),
        dates: [new Date(2026, 9, 18), new Date(2026, 9, 17, 23, 59)],
        titles: ["Last 7 days", "Earlier"],
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
        titles: ["Yesterday", "Last 7 days", "Last 7 days", "Earlier"],
    },
    {
        name: "seven-day range spans month and daylight-saving boundaries",
        now: new Date(2026, 10, 4, 12),
        dates: [
            new Date(2026, 10, 2),
            new Date(2026, 10, 1),
            new Date(2026, 9, 28),
            new Date(2026, 9, 27, 23, 59),
        ],
        titles: ["Last 7 days", "Last 7 days", "Last 7 days", "Earlier"],
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
