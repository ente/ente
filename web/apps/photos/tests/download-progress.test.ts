import { downloadProgressState } from "ente-gallery/components/viewer/download-progress";
import { describe, expect, test } from "vitest";

const loading = { isContentLoading: true };

describe("downloadProgressState", () => {
    test("keeps decrypting during the live-photo conversion tail", () => {
        const downloaded = downloadProgressState(
            loading,
            { loaded: 100, total: 100 },
            undefined,
        );
        expect(downloaded).toEqual({
            phase: "decrypting",
            percentage: 100,
            loaded: 100,
            total: 100,
        });
        const tail = downloadProgressState(loading, undefined, downloaded);
        expect(tail).toEqual({ phase: "decrypting", percentage: 100 });
        expect(downloadProgressState(loading, undefined, tail)).toEqual(tail);
    });

    test("prepares HLS auto video without a download entry, then hides", () => {
        const preparing = downloadProgressState(loading, undefined, undefined);
        expect(preparing).toEqual({ phase: "preparing", percentage: 0 });
        expect(downloadProgressState({}, undefined, preparing)).toBeUndefined();
    });

    test("hides cached content regardless of previous progress or an entry", () => {
        expect(
            downloadProgressState(
                {},
                { loaded: 30, total: 100 },
                { phase: "downloading", percentage: 30 },
            ),
        ).toBeUndefined();
        expect(
            downloadProgressState({}, undefined, {
                phase: "failed",
                percentage: 70,
            }),
        ).toBeUndefined();
    });

    test("shows decrypting when downloaded bytes exceed the reported total", () => {
        expect(
            downloadProgressState(
                loading,
                { loaded: 117, total: 100 },
                undefined,
            ),
        ).toEqual({
            phase: "decrypting",
            percentage: 100,
            loaded: 117,
            total: 100,
        });
    });

    test("shows unknown totals as indeterminate and retains the download tail", () => {
        const state = downloadProgressState(
            loading,
            { loaded: 30, total: undefined },
            undefined,
        );
        expect(state).toEqual({
            phase: "downloading",
            percentage: undefined,
            loaded: 30,
        });
        const completed = downloadProgressState(
            loading,
            { loaded: 30, total: 30 },
            state,
        );
        expect(downloadProgressState(loading, undefined, completed)).toEqual({
            phase: "decrypting",
            percentage: 100,
        });
    });

    test("keeps partial progress when the entry is removed before failure", () => {
        const downloading = downloadProgressState(
            loading,
            { loaded: 42, total: 100 },
            undefined,
        );
        const removed = downloadProgressState(loading, undefined, downloading);
        expect(removed).toEqual({ phase: "downloading", percentage: 42 });
        expect(
            downloadProgressState({ fetchFailed: true }, undefined, removed),
        ).toEqual({ phase: "failed", percentage: 42 });
    });

    test("failure takes precedence and keeps the previous percentage", () => {
        expect(
            downloadProgressState({ fetchFailed: true }, undefined, {
                phase: "downloading",
                percentage: 42,
            }),
        ).toEqual({ phase: "failed", percentage: 42 });
        expect(
            downloadProgressState(
                { ...loading, fetchFailed: true },
                { loaded: 100, total: 100 },
                undefined,
            ),
        ).toEqual({ phase: "failed", percentage: 0 });
    });

    test("retry ignores the previous failed percentage", () => {
        expect(
            downloadProgressState(loading, undefined, {
                phase: "failed",
                percentage: 42,
            }),
        ).toEqual({ phase: "preparing", percentage: 0 });
    });

    test("opens on an in-flight download without previous state", () => {
        expect(
            downloadProgressState(
                loading,
                { loaded: 30, total: 100 },
                undefined,
            ),
        ).toEqual({
            phase: "downloading",
            percentage: 30,
            loaded: 30,
            total: 100,
        });
    });

    test("prepares a known total with no bytes and floors partial percentages", () => {
        expect(
            downloadProgressState(
                loading,
                { loaded: 0, total: 100 },
                undefined,
            ),
        ).toEqual({ phase: "preparing", percentage: 0 });
        expect(
            downloadProgressState(
                loading,
                { loaded: 9999, total: 10000 },
                undefined,
            )?.percentage,
        ).toBe(99);
    });
});
