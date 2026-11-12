import { ThemeProvider } from "@mui/material";
import { photosTheme } from "ente-base/components/utils/theme";
import { UploadCompletion } from "ente-gallery/components/UploadCompletion";
import type { SegregatedFinishedUploads } from "ente-gallery/components/upload-progress-stats";
import type { PropsWithChildren } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test, vi } from "vitest";

vi.mock("@mui/material", async (importOriginal) => ({
    ...(await importOriginal<typeof import("@mui/material")>()),
    Dialog: ({ children }: PropsWithChildren) => <div>{children}</div>,
}));
vi.mock("i18next", () => ({ t: (key: string) => key }));
vi.mock("ente-new/photos/components/mui/SlideUpTransition", () => ({
    SlideUpTransition: () => null,
}));

const renderCompletion = (finishedUploads: SegregatedFinishedUploads) =>
    renderToStaticMarkup(
        <ThemeProvider theme={photosTheme}>
            <UploadCompletion
                open
                onClose={vi.fn()}
                onReviewFailed={vi.fn()}
                finishedUploads={finishedUploads}
            />
        </ThemeProvider>,
    );

describe("upload completion", () => {
    test("shows an error when every upload fails, including blocked uploads", () => {
        const html = renderCompletion(
            new Map([
                ["failed", [1]],
                ["blocked", [2]],
            ]),
        );
        expect(html).toContain("upload_completion_failed_title");
        expect(html).toContain("upload_completion_failed_subtitle");
        expect(html).toContain("/images/warning-red.png");
        expect(html).toContain(
            "background-color:var(--mui-palette-critical-dark)",
        );
    });

    test.each(["failed", "blocked"] as const)(
        "shows an error when one upload is %s among successful and skipped uploads",
        (failureType) => {
            const html = renderCompletion(
                new Map([
                    ["uploaded", [1]],
                    [failureType, [2]],
                    ["unsupported", [3]],
                ]),
            );
            expect(html).toContain("upload_completion_partial_failure_title");
            expect(html).toContain(
                "upload_completion_partial_failure_subtitle",
            );
            expect(html).toContain("/images/warning-red.png");
            expect(html).toContain(
                "background-color:var(--mui-palette-critical-dark)",
            );
        },
    );

    test("keeps skipped-only review neutral to failures", () => {
        const html = renderCompletion(new Map([["unsupported", [1]]]));
        expect(html).not.toContain("upload_completion_failed_title");
        expect(html).toContain("review_items");
        expect(html).not.toContain(
            "background-color:var(--mui-palette-critical-dark)",
        );
    });
});
