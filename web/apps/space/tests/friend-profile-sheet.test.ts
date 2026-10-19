import { describe, expect, it } from "vitest";
import {
    friendSheetSnap,
    stepFriendSheetSpring,
} from "../src/utils/friend-profile-sheet";

describe("friend profile sheet motion", () => {
    it("continues from the released position instead of jumping to a snap point", () => {
        const next = stepFriendSheetSpring(260, -400, 0, 16);
        expect(next.position).toBeLessThan(260);
        expect(next.position).toBeGreaterThan(200);
    });

    it("uses elapsed time consistently across refresh rates", () => {
        const step = stepFriendSheetSpring(400, -300, 0, 32);
        const first = stepFriendSheetSpring(400, -300, 0, 16);
        const second = stepFriendSheetSpring(
            first.position,
            first.velocity,
            0,
            16,
        );
        expect(second.position).toBeCloseTo(step.position, 8);
        expect(second.velocity).toBeCloseTo(step.velocity, 8);
    });

    it("settles downward at the bottom of the viewport", () => {
        let motion = { position: 400, velocity: 0 };
        for (let frame = 0; frame < 60; frame++) {
            const next = stepFriendSheetSpring(
                motion.position,
                motion.velocity,
                844,
                1000 / 60,
            );
            expect(next.position).toBeGreaterThanOrEqual(motion.position);
            expect(next.position).toBeLessThanOrEqual(844);
            motion = next;
        }
        expect(motion.position).toBeCloseTo(844, 2);
    });

    it.each([
        [250, -900, "expanded"],
        [460, 0, "collapsed"],
        [540, 1200, "closed"],
        [520, -1400, "expanded"],
    ])(
        "snaps position %s with velocity %s to %s",
        (position, velocity, snap) => {
            expect(friendSheetSnap(position, velocity, 460, 844)).toBe(snap);
        },
    );
});
