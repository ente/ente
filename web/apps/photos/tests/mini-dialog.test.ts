import { miniDialogReducer } from "ente-base/components/utils/mini-dialog-state";
import { describe, expect, test, vi } from "vitest";
import { trashFilesDialogAttributes } from "../src/components/utils/dialog-attributes";

vi.mock("i18next", () => ({
    t: (key: string, options?: { count?: number }) =>
        options?.count === undefined ? key : `${key}:${options.count}`,
}));

describe("mini dialog lifecycle", () => {
    test("navigation clears the trash confirmation and its captured action", () => {
        const action = vi.fn();
        const prompt = miniDialogReducer(
            { open: false, id: 0 },
            { type: "show", attributes: trashFilesDialogAttributes(3, action) },
        );
        const dismissed = miniDialogReducer(prompt, { type: "routeChange" });
        expect(dismissed.open).toBe(false);
        expect(dismissed.attributes).toBeUndefined();
        expect(dismissed.id).not.toBe(prompt.id);
        expect(action).not.toHaveBeenCalled();

        const next = miniDialogReducer(dismissed, {
            type: "show",
            attributes: { title: "Another page" },
        });
        expect(miniDialogReducer(next, { type: "close", id: prompt.id })).toBe(
            next,
        );
    });

    test("navigation preserves app-wide prompts, including session expiry", () => {
        const prompt = miniDialogReducer(
            { open: false, id: 0 },
            {
                type: "show",
                attributes: {
                    title: "Session expired",
                    nonClosable: true,
                    nonReplaceable: true,
                },
            },
        );
        expect(miniDialogReducer(prompt, { type: "routeChange" })).toBe(prompt);
    });

    test("an earlier action cannot close a follow-up notice", () => {
        const first = miniDialogReducer(
            { open: false, id: 0 },
            { type: "show", attributes: { title: "Delete?" } },
        );
        const notice = miniDialogReducer(first, {
            type: "show",
            attributes: { title: "Some files belong to others" },
        });
        expect(miniDialogReducer(notice, { type: "close", id: first.id })).toBe(
            notice,
        );
        expect(notice.open).toBe(true);
        expect(notice.id).not.toBe(first.id);
    });

    test("non-replaceable prompts block replacement only while open", () => {
        const locked = miniDialogReducer(
            { open: false, id: 0 },
            { type: "show", attributes: { nonReplaceable: true } },
        );
        const show = { type: "show", attributes: { title: "Next" } } as const;
        expect(miniDialogReducer(locked, show)).toBe(locked);
        const closed = miniDialogReducer(locked, {
            type: "close",
            id: locked.id,
        });
        expect(closed.open).toBe(false);
        const next = miniDialogReducer(closed, show);
        expect(next.open).toBe(true);
        expect(next.attributes?.title).toBe("Next");
        expect(next.id).not.toBe(locked.id);
    });

    test("showing the same attributes again creates fresh component state", () => {
        const attributes = { title: "Retry" };
        const first = miniDialogReducer(
            { open: false, id: 0 },
            { type: "show", attributes },
        );
        const next = miniDialogReducer(first, { type: "show", attributes });
        expect(next.id).toBe(first.id + 1);
    });
});

describe("trash confirmation attributes", () => {
    test.each([1, 12])(
        "uses the owned count %i and a critical action",
        (count) => {
            const attributes = trashFilesDialogAttributes(count, vi.fn());
            expect(attributes.title).toBe(`trash_items_title:${count}`);
            expect(attributes.message).toBe(`trash_items_message:${count}`);
            expect(attributes.kind).toBe("warning");
            expect(attributes.dismissOnRouteChange).toBe(true);
            expect(attributes.continue?.color).toBe("critical");
            expect(attributes.continue?.text).toBe("move_to_trash");
        },
    );

    test("keeps the action pending until the operation finishes", async () => {
        let finish!: () => void;
        const operation = new Promise<void>((resolve) => {
            finish = resolve;
        });
        const attributes = trashFilesDialogAttributes(1, () => operation);
        const completed = vi.fn();
        const result = Promise.resolve(attributes.continue?.action?.()).then(
            completed,
        );
        await Promise.resolve();
        expect(completed).not.toHaveBeenCalled();
        finish();
        await result;
        expect(completed).toHaveBeenCalledOnce();
    });

    test("passes failures through for the inline retry state", async () => {
        const failure = new Error("Trash failed");
        const attributes = trashFilesDialogAttributes(1, () =>
            Promise.reject(failure),
        );
        await expect(attributes.continue?.action?.()).rejects.toBe(failure);
    });
});
