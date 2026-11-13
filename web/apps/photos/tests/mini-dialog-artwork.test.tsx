import { ThemeProvider } from "@mui/material";
import {
    AttributedMiniDialog,
    type MiniDialogAttributes,
} from "ente-base/components/MiniDialog";
import { photosTheme } from "ente-base/components/utils/theme";
import type { PropsWithChildren } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test, vi } from "vitest";

// Render portal contents on the server so artwork assertions inspect real markup.
vi.mock("@mui/material", async (importOriginal) => ({
    ...(await importOriginal<typeof import("@mui/material")>()),
    Dialog: ({ children }: PropsWithChildren) => <div>{children}</div>,
}));

const renderDialog = (
    attributes: MiniDialogAttributes,
    appearance: "default" | "centered" = "centered",
) =>
    renderToStaticMarkup(
        <ThemeProvider theme={photosTheme}>
            <AttributedMiniDialog
                open
                appearance={appearance}
                onClose={vi.fn()}
                attributes={{ title: "Confirm", cancel: false, ...attributes }}
            />
        </ThemeProvider>,
    );

describe("mini dialog artwork", () => {
    test.each([
        ["info", "grey"],
        ["warning", "red"],
        ["error", "grey"],
    ] as const)("renders %s artwork in centered dialogs", (kind, color) => {
        const html = renderDialog({ kind });
        expect(html).toContain(`src="/images/warning-${color}.png"`);
        expect(html).toContain('alt=""');
        expect(html).toContain("width:68px;height:64px;object-fit:contain");
    });

    test("explicit artwork overrides the kind and icon", () => {
        const html = renderDialog({
            kind: "warning",
            illustration: <span>Custom artwork</span>,
            icon: <span>Fallback icon</span>,
        });
        expect(html).toContain("Custom artwork");
        expect(html).not.toContain("warning-red.png");
        expect(html).not.toContain("Fallback icon");
    });

    test("kind artwork overrides the fallback icon", () => {
        const html = renderDialog({
            kind: "info",
            icon: <span>Fallback icon</span>,
        });
        expect(html).toContain("warning-grey.png");
        expect(html).not.toContain("Fallback icon");
    });

    test("retains consumer icons when no kind or illustration is supplied", () => {
        expect(renderDialog({ icon: <span>Info icon</span> })).toContain(
            "Info icon",
        );
    });

    test("omits artwork when none is supplied", () => {
        const html = renderDialog({});
        expect(html).not.toContain("<img");
        expect(html).toContain("padding-top:64px");
    });

    test.each(["info", "warning", "error"] as const)(
        "default dialogs preserve their icon and do not load %s artwork",
        (kind) => {
            const html = renderDialog(
                { kind, icon: <span>Original icon</span> },
                "default",
            );
            expect(html).toContain("Original icon");
            expect(html).not.toContain("/images/warning-");
        },
    );
});
