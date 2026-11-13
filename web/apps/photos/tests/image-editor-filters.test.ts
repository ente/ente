import {
    applyEditorFilter,
    editorFilterPresets,
} from "ente-new/photos/components/ImageEditor.filters";
import { describe, expect, test } from "vitest";

describe("image editor filter presets", () => {
    test.each([
        ["None", [100, 150, 200]],
        ["Pop", [80, 175, 255]],
        ["Amber", [64, 168, 252]],
        ["Dust", [148, 167, 181]],
        ["Carbon", [150, 150, 150]],
        ["Glacier", [63, 156, 161]],
        ["Haze", [66, 111, 136]],
        ["Meadow", [105, 165, 200]],
        ["Zest", [85, 173, 255]],
        ["Retro", [117, 137, 160]],
        ["Sepia", [99, 147, 195]],
    ])("%s matches the mobile Dart filter output", (name, expected) => {
        const pixels = new Uint8ClampedArray([100, 150, 200, 127]);
        const preset = editorFilterPresets.find(
            (preset) => preset.name === name,
        )!;
        applyEditorFilter(pixels, preset.matrix);
        expect([...pixels]).toEqual([...expected, 127]);
    });

    test("None preserves every channel, including transparent pixels", () => {
        const pixels = new Uint8ClampedArray([
            0, 128, 255, 0, 250, 30, 15, 255,
        ]);
        const original = pixels.slice();
        applyEditorFilter(pixels, editorFilterPresets[0]!.matrix);
        expect(pixels).toEqual(original);
    });

    test("Carbon keeps output grayscale across different colors", () => {
        const pixels = new Uint8ClampedArray([255, 0, 0, 255, 0, 255, 0, 200]);
        const carbon = editorFilterPresets.find(
            ({ name }) => name === "Carbon",
        )!;
        applyEditorFilter(pixels, carbon.matrix);
        for (let i = 0; i < pixels.length; i += 4) {
            expect(pixels[i]).toBe(pixels[i + 1]);
            expect(pixels[i]).toBe(pixels[i + 2]);
        }
        expect(pixels[3]).toBe(255);
        expect(pixels[7]).toBe(200);
    });
});
