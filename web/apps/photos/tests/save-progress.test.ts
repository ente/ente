import {
    isSaveComplete,
    type SaveGroup,
} from "ente-gallery/components/utils/save-groups";
import { createSaveProgress } from "ente-gallery/services/save-progress";
import type { EnteFile } from "ente-media/file";
import { describe, expect, test, vi } from "vitest";

const file = (id: number, fileSize?: number) =>
    ({ id, info: { fileSize } }) as EnteFile;

const setup = (files: EnteFile[]) => {
    let group = {} as SaveGroup;
    const progress = createSaveProgress(files, (tx) => {
        group = tx(group);
    });
    return { progress, value: () => group.downloadProgress };
};

describe("save byte progress", () => {
    test("waits for the ZIP handoff even when every file has been downloaded", () => {
        const group = {
            total: 2,
            success: 2,
            failed: 0,
            isFinalizing: true,
        } as SaveGroup;
        expect(isSaveComplete(group)).toBe(false);
        expect(isSaveComplete({ ...group, isFinalizing: false })).toBe(true);
    });
    test("weights concurrent files by bytes rather than file count", () => {
        const small = file(1, 10);
        const large = file(2, 90);
        const { progress, value } = setup([small, large]);
        progress.update(small, { loaded: 10, total: 10 });
        expect(value()).toBe(0.1);
        progress.update(large, { loaded: 90, total: 90 });
        expect(value()).toBe(1);
    });

    test("keeps successful bytes and resets only a retried file", () => {
        const small = file(1, 10);
        const large = file(2, 90);
        const { progress, value } = setup([small, large]);
        progress.update(small, { loaded: 10, total: 10 });
        progress.update(large, { loaded: 90, total: 90 });
        progress.start(large);
        expect(value()).toBe(0.1);
        progress.update(large, { loaded: 90, total: 90 });
        expect(value()).toBe(1);
    });

    test("waits for missing sizes instead of estimating by file count", () => {
        const unknown = file(1);
        const known = file(2, 90);
        const { progress, value } = setup([unknown, known]);
        progress.update(known, { loaded: 90, total: 90 });
        expect(value()).toBeUndefined();
        progress.update(unknown, { loaded: 10, total: 10 });
        expect(value()).toBe(1);
    });

    test("reports partial byte progress with throttled updates", () => {
        const large = file(1, 1000);
        const { progress, value } = setup([large]);
        const clock = vi.spyOn(performance, "now");
        try {
            clock.mockReturnValue(0);
            progress.update(large, { loaded: 100, total: 1000 });
            expect(value()).toBe(0.1);
            clock.mockReturnValue(50);
            progress.update(large, { loaded: 200, total: 1000 });
            expect(value()).toBe(0.1);
            clock.mockReturnValue(100);
            progress.update(large, { loaded: 300, total: 1000 });
            expect(value()).toBe(0.3);
        } finally {
            clock.mockRestore();
        }
    });
});
