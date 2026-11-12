import { normalizePercent } from "ente-gallery/components/upload-progress/helpers";
import { expect, test } from "vitest";

test("floors upload percentages and clamps them to the valid range", () => {
    const screenshotProgress = (2716 / 2721) * 100;
    expect(Math.round(screenshotProgress)).toBe(100);
    expect(normalizePercent(screenshotProgress)).toBe(99);
    expect(normalizePercent(99.999)).toBe(99);
    expect(normalizePercent(42.6)).toBe(42);
    expect(normalizePercent(100)).toBe(100);
    expect(normalizePercent(101)).toBe(100);
    expect(normalizePercent(-1)).toBe(0);
    expect(normalizePercent(NaN)).toBe(0);
});
