import assert from "node:assert/strict";
import { test } from "vitest";
import { getPhotoDrawLayout } from "./photoCrop";
import type { PhotoSlot } from "./types";

const slot: PhotoSlot = {
    id: "slot",
    photoId: "photo",
    x: 10,
    y: 20,
    width: 60,
    height: 40,
    cropX: 0.5,
    cropY: 0.5,
    cropZoom: 1,
};

test("legacy photos keep their original centered crop without a rotation value", () => {
    const draw = getPhotoDrawLayout(slot, 1200, 800, 1000, 1000);
    assert.deepEqual(draw, {
        x: 400,
        y: 400,
        width: 600,
        height: 400,
        rotation: 0,
        slackX: 0,
        slackY: 0,
    });
});

test("quarter turns fill the same frame without stretching the photo", () => {
    for (const rotation of [90, 270]) {
        const draw = getPhotoDrawLayout(
            { ...slot, rotation },
            1200,
            800,
            1000,
            1000,
        );
        assert.equal(draw.x, 400);
        assert.equal(draw.y, 400);
        assert.equal(draw.width, 900);
        assert.equal(draw.height, 600);
        assert.equal(draw.width / draw.height, 1200 / 800);
        assert.equal(draw.slackX, 0);
        assert.equal(draw.slackY, -500);
        assert.equal(draw.rotation, rotation);
    }
});

test("all rotations and crop positions cover the frame at every supported zoom", () => {
    for (const rotation of [0, 90, 180, 270]) {
        for (const cropZoom of [1, 1.2, 3]) {
            for (const cropX of [0, 0.5, 1]) {
                for (const cropY of [0, 0.5, 1]) {
                    const draw = getPhotoDrawLayout(
                        { ...slot, rotation, cropZoom, cropX, cropY },
                        800,
                        1200,
                        1000,
                        1000,
                    );
                    const width = rotation % 180 ? draw.height : draw.width;
                    const height = rotation % 180 ? draw.width : draw.height;
                    assert.ok(draw.x - width / 2 <= 100 + 1e-8);
                    assert.ok(draw.x + width / 2 >= 700 - 1e-8);
                    assert.ok(draw.y - height / 2 <= 200 + 1e-8);
                    assert.ok(draw.y + height / 2 >= 600 - 1e-8);
                    assert.ok(draw.slackX <= 1e-8);
                    assert.ok(draw.slackY <= 1e-8);
                }
            }
        }
    }
});
