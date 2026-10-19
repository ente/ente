import { describe, expect, it } from "vitest";
import {
    arrangeFriendOrbit,
    createFriendOrbitCircle,
    friendOrbitCircleSize,
    stepFriendOrbit,
} from "../src/utils/friend-orbit";

describe("friend orbit", () => {
    it("completes the reference orbit in four minutes", () => {
        const bounds = { width: 1280, height: 720, scale: 1.4 };
        const circles = Array.from({ length: 2 }, (_, index) =>
            createFriendOrbitCircle(String(index), index),
        );
        arrangeFriendOrbit(circles, bounds, 60000);
        for (const circle of circles) {
            expect(circle.x).toBeCloseTo(-circle.homeY);
            expect(circle.y).toBeCloseTo(circle.homeX);
        }
        arrangeFriendOrbit(circles, bounds, 240000);
        for (const circle of circles) {
            expect(circle.x).toBeCloseTo(circle.homeX);
            expect(circle.y).toBeCloseTo(circle.homeY);
        }
    });

    for (const [width, height, scale, count] of [
        [1280, 664, 1.4, 9],
        [390, 728, 0.84, 1],
        [390, 728, 0.84, 3],
        [390, 728, 0.84, 9],
        [320, 452, 0.84, 9],
        [390, 728, 0.84, 30],
        [390, 728, 0.84, 36],
    ] as const) {
        it(`keeps ${count} friends separated and in bounds at ${width}px`, () => {
            const bounds = { width, height, scale };
            const circles = Array.from({ length: count }, (_, index) => ({
                ...createFriendOrbitCircle(String(index), index),
                size: friendOrbitCircleSize(index, count, bounds),
            }));
            arrangeFriendOrbit(circles, bounds, 0);
            for (let frame = 0; frame < 600; frame++) {
                stepFriendOrbit(circles, bounds, frame * 16.667, 16.667);
                for (const circle of circles) {
                    const radius = circle.size / 2;
                    expect(Math.abs(circle.x) + radius).toBeLessThanOrEqual(
                        width / (2 * scale) + 0.01,
                    );
                    expect(Math.abs(circle.y) + radius).toBeLessThanOrEqual(
                        height / (2 * scale) + 0.01,
                    );
                }
            }
            for (let i = 0; i < circles.length; i++) {
                for (let j = i + 1; j < circles.length; j++) {
                    const first = circles[i]!;
                    const second = circles[j]!;
                    expect(
                        Math.hypot(first.x - second.x, first.y - second.y),
                    ).toBeGreaterThanOrEqual((first.size + second.size) / 2);
                }
            }
        });
    }

    it("starts settled and keeps moving smoothly after the page appears", () => {
        const bounds = { width: 390, height: 728, scale: 0.84 };
        const circles = Array.from({ length: 9 }, (_, index) => ({
            ...createFriendOrbitCircle(String(index), index),
            size: friendOrbitCircleSize(index, 9, bounds),
        }));
        arrangeFriendOrbit(circles, bounds, 0);
        const initial = circles.map(({ x, y }) => ({ x, y }));
        for (let frame = 1; frame <= 180; frame++) {
            const previous = circles.map(({ x, y }) => ({ x, y }));
            stepFriendOrbit(circles, bounds, frame * 16.667, 16.667);
            circles.forEach((circle, index) => {
                expect(
                    Math.hypot(
                        circle.x - previous[index]!.x,
                        circle.y - previous[index]!.y,
                    ),
                ).toBeLessThan(2);
            });
        }
        circles.forEach((circle, index) => {
            expect(
                Math.hypot(
                    circle.x - initial[index]!.x,
                    circle.y - initial[index]!.y,
                ),
            ).toBeGreaterThan(0.5);
        });
    });

    it("makes small groups larger and crowded groups smaller without tiny targets", () => {
        const bounds = { width: 390, height: 728, scale: 0.84 };
        for (let index = 0; index < 3; index++) {
            expect(friendOrbitCircleSize(index, 3, bounds)).toBeGreaterThan(
                friendOrbitCircleSize(index, 9, bounds),
            );
            expect(friendOrbitCircleSize(index, 9, bounds)).toBeGreaterThan(
                friendOrbitCircleSize(index, 36, bounds),
            );
        }
        for (let index = 0; index < 100; index++) {
            expect(
                friendOrbitCircleSize(index, 100, bounds) * bounds.scale,
            ).toBeGreaterThanOrEqual(48);
        }
        expect(friendOrbitCircleSize(0, 1, bounds) * bounds.scale).toBeLessThan(
            bounds.width - 24,
        );
    });

    it("keeps a held circle under the pointer and moves neighbors aside", () => {
        const first = createFriendOrbitCircle("first", 0);
        const second = createFriendOrbitCircle("second", 1);
        first.x = second.x = 0;
        first.y = second.y = 0;
        stepFriendOrbit(
            [first, second],
            { width: 1280, height: 720, scale: 1.4 },
            0,
            16.667,
            first.id,
        );
        expect(first.x).toBe(0);
        expect(first.y).toBe(0);
        expect(Math.hypot(second.x, second.y)).toBeGreaterThanOrEqual(
            (first.size + second.size) / 2,
        );
    });

    it("eases a released circle back without saving the dragged position", () => {
        const circle = createFriendOrbitCircle("friend", 0);
        circle.x = 160;
        circle.y = 90;
        const bounds = { width: 1280, height: 720, scale: 1.4 };
        stepFriendOrbit([circle], bounds, 0, 16.667, undefined, true);
        expect(circle.x).toBeLessThan(160);
        expect(circle.x).toBeGreaterThan(circle.homeX);
        for (let i = 0; i < 300; i++)
            stepFriendOrbit([circle], bounds, 0, 16.667, undefined, true);
        expect(circle.x).toBeCloseTo(circle.homeX);
        expect(circle.y).toBeCloseTo(circle.homeY);
    });

    it("does not drift when reduced motion is enabled", () => {
        const circle = createFriendOrbitCircle("friend", 0);
        for (let i = 0; i < 60; i++) {
            stepFriendOrbit(
                [circle],
                { width: 1280, height: 720, scale: 1.4 },
                0,
                16.667,
                undefined,
                true,
            );
        }
        expect(circle.x).toBe(circle.homeX);
        expect(circle.y).toBe(circle.homeY);
    });
});
