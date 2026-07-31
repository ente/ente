import { mlIndexFlagsForRustResult } from "ente-new/photos/services/ml/index-flags";
import { describe, expect, test } from "vitest";

describe("ML index runtime flags", () => {
    test.each([
        [false, false, 1],
        [true, false, 3],
        [false, true, 5],
        [true, true, 7],
    ])(
        "encodes CoreML=%s and WebGPU=%s as %d",
        (usedCoreml, usedWebgpu, expected) => {
            expect(mlIndexFlagsForRustResult({ usedCoreml, usedWebgpu })).toBe(
                expected,
            );
        },
    );
});
