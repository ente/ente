import { Copy01Icon, ReloadIcon, Tick02Icon } from "@hugeicons/core-free-icons";
import { ThemeProvider } from "@mui/material";
import {
    Notification,
    type NotificationAttributes,
} from "ente-base/components/Notification";
import { photosTheme } from "ente-base/components/utils/theme";
import i18next from "i18next";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeAll, describe, expect, test, vi } from "vitest";

beforeAll(async () => {
    await i18next.init({
        lng: "en",
        resources: { en: { translation: { close: "Close" } } },
    });
});

const renderNotification = (attributes: Partial<NotificationAttributes>) =>
    renderToStaticMarkup(
        <ThemeProvider theme={photosTheme}>
            <Notification
                open
                onClose={vi.fn()}
                attributes={{
                    color: "secondary",
                    title: "Done",
                    ...attributes,
                }}
            />
        </ThemeProvider>,
    );

describe("notification icons", () => {
    test("renders imported icon data at the shared sizes", () => {
        const markup = renderNotification({
            startIcon: Tick02Icon,
            endIcon: ReloadIcon,
            endIconLabel: "Retry",
        });
        const icons = markup.match(/<svg\b[^>]*>/g) ?? [];
        expect(icons).toHaveLength(3);
        expect(icons[0]).toContain('width="24"');
        expect(icons[1]).toContain('width="22"');
        expect(icons[2]).toContain('width="22"');
        for (const icon of icons) expect(icon).toContain('stroke-width="1.8"');
        expect(markup).toContain('aria-label="Retry"');
    });

    test("uses the same default size and color for copy and copied icons", () => {
        for (const endIcon of [Copy01Icon, Tick02Icon]) {
            const markup = renderNotification({
                color: "inherit",
                startIcon: null,
                endIcon,
            });
            const icons = markup.match(/<svg\b[^>]*>/g) ?? [];
            expect(icons).toHaveLength(2);
            for (const icon of icons) expect(icon).toContain('width="22"');
            expect(markup).not.toContain(
                "color:var(--mui-palette-success-main)",
            );
        }
    });

    test("keeps the default leading icon and allows explicitly omitting it", () => {
        const defaultMarkup = renderNotification({});
        const noLeadingIconMarkup = renderNotification({ startIcon: null });
        expect(defaultMarkup.match(/<svg\b/g)).toHaveLength(2);
        expect(noLeadingIconMarkup.match(/<svg\b/g)).toHaveLength(1);
    });
});

describe("notification accessibility", () => {
    test.each([
        {
            title: "Renew now",
            caption: "Subscription expired",
            captionText: "Subscription expired",
        },
        {
            title: "Summer vacation",
            caption: <span>Downloading · 4 / 10 files</span>,
            captionText: "Downloading · 4 / 10 files",
        },
    ])(
        "exposes title and caption in the $title button",
        ({ title, caption, captionText }) => {
            const markup = renderNotification({
                title,
                caption,
                onClick: vi.fn(),
                endIcon: ReloadIcon,
                endIconLabel: "Retry",
                onEndIconClick: vi.fn(),
            });
            const buttons = [
                ...markup.matchAll(/<button\b([^>]*)>([\s\S]*?)<\/button>/g),
            ];
            expect(buttons).toHaveLength(3);
            const mainButton = buttons[0]!;
            const text = mainButton[2]!
                .replace(/<style\b[^>]*>[\s\S]*?<\/style>/g, "")
                .replace(/<[^>]*>/g, " ")
                .replace(/\s+/g, " ")
                .trim();
            expect(text).toBe(`${title} ${captionText}`);
            expect(mainButton[1]).not.toContain("aria-label=");
            const contentID = /id="([^"]+)" role="status"/.exec(
                mainButton[2]!,
            )?.[1];
            expect(contentID).toBeDefined();
            expect(mainButton[1]).toContain(`aria-labelledby="${contentID}"`);
            expect(buttons[1]![1]).toContain('aria-label="Retry"');
            expect(buttons[2]![1]).toContain('aria-label="Close"');
        },
    );
});
