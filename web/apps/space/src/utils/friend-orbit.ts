export interface FriendOrbitCircle {
    id: string;
    homeX: number;
    homeY: number;
    x: number;
    y: number;
    vx: number;
    vy: number;
    size: number;
}

export interface FriendOrbitBounds {
    width: number;
    height: number;
    scale: number;
}

const circleSizes = [144, 64, 88, 68, 136, 112, 148, 72, 64];

export const createFriendOrbitCircle = (
    id: string,
    index: number,
): FriendOrbitCircle => {
    const angle = index * 2.399963229728653;
    const radius = 22 * Math.sqrt(index);
    const homeX = Math.cos(angle) * radius;
    const homeY = Math.sin(angle) * radius;
    return {
        id,
        homeX,
        homeY,
        x: homeX,
        y: homeY,
        vx: 0,
        vy: 0,
        size: circleSizes[index % circleSizes.length]!,
    };
};

export const friendOrbitCircleSize = (
    index: number,
    count: number,
    bounds: FriendOrbitBounds,
) => {
    const diameter =
        circleSizes[index % circleSizes.length]! *
        bounds.scale *
        Math.sqrt(9 / count);
    const maximum = Math.min(280, bounds.width * 0.68, bounds.height * 0.5);
    return Math.max(48, Math.min(maximum, diameter)) / bounds.scale;
};

const friendOrbitAngle = (elapsed: number) => (elapsed / 240000) * Math.PI * 2;

export const stepFriendOrbit = (
    circles: FriendOrbitCircle[],
    bounds: FriendOrbitBounds,
    elapsed: number,
    delta: number,
    draggedID?: string,
    reducedMotion = false,
) => {
    const angle = friendOrbitAngle(elapsed);
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);
    const frame = Math.min(delta / 16.667, 2);
    const damping = 0.87 ** frame;
    circles.forEach((circle, index) => {
        if (circle.id == draggedID) return;
        const driftX = reducedMotion
            ? 0
            : Math.sin(elapsed * 0.00034 + index * 1.71) * 3.5;
        const driftY = reducedMotion
            ? 0
            : Math.cos(elapsed * 0.00029 + index * 2.03) * 3.5;
        const x = circle.homeX + driftX;
        const y = circle.homeY + driftY;
        circle.vx =
            (circle.vx + (x * cos - y * sin - circle.x) * 0.018 * frame) *
            damping;
        circle.vy =
            (circle.vy + (x * sin + y * cos - circle.y) * 0.018 * frame) *
            damping;
        circle.x += circle.vx * frame;
        circle.y += circle.vy * frame;
    });

    for (let pass = 0; pass < 7; pass++) {
        for (let i = 0; i < circles.length; i++) {
            const first = circles[i]!;
            for (let j = i + 1; j < circles.length; j++) {
                const second = circles[j]!;
                const dx = second.x - first.x;
                const dy = second.y - first.y;
                const separation = (first.size + second.size) / 2 + 10;
                if (Math.abs(dx) >= separation || Math.abs(dy) >= separation)
                    continue;
                const distance = Math.hypot(dx, dy);
                if (distance >= separation) continue;
                const nx = distance < 0.001 ? Math.cos(i + j) : dx / distance;
                const ny = distance < 0.001 ? Math.sin(i + j) : dy / distance;
                const push = separation - distance;
                const firstShare =
                    first.id == draggedID
                        ? 0
                        : second.id == draggedID
                          ? 1
                          : 0.505;
                const secondShare =
                    second.id == draggedID
                        ? 0
                        : first.id == draggedID
                          ? 1
                          : 0.505;
                first.x -= nx * push * firstShare;
                first.y -= ny * push * firstShare;
                second.x += nx * push * secondShare;
                second.y += ny * push * secondShare;
            }
        }
        circles.forEach((circle) => {
            if (circle.id == draggedID) return;
            const radius = circle.size / 2 + 12 / bounds.scale;
            const halfWidth = bounds.width / (2 * bounds.scale);
            const halfHeight = bounds.height / (2 * bounds.scale);
            circle.x = Math.max(
                -halfWidth + radius,
                Math.min(halfWidth - radius, circle.x),
            );
            circle.y = Math.max(
                -halfHeight + radius,
                Math.min(halfHeight - radius, circle.y),
            );
        });
    }
};

export const arrangeFriendOrbit = (
    circles: FriendOrbitCircle[],
    bounds: FriendOrbitBounds,
    elapsed: number,
    initialOuterID?: string,
) => {
    circles.forEach((circle, index) => {
        const initial = createFriendOrbitCircle(circle.id, index);
        Object.assign(circle, initial, { size: circle.size });
    });
    const group = circles.filter((circle) => circle.id != initialOuterID);
    for (let frame = 0; frame < 90; frame++) {
        stepFriendOrbit(group, bounds, 0, 16.667, undefined, true);
    }
    const outer = circles.find((circle) => circle.id == initialOuterID);
    if (outer && group.length) {
        const neighbor = group.reduce((top, circle) =>
            circle.y - circle.size / 2 < top.y - top.size / 2 ? circle : top,
        );
        outer.x = neighbor.x;
        outer.y = neighbor.y - (neighbor.size + outer.size) / 2 - 10;
    }
    const angle = friendOrbitAngle(elapsed);
    circles.forEach((circle) => {
        circle.homeX = circle.x;
        circle.homeY = circle.y;
        circle.vx = 0;
        circle.vy = 0;
        circle.x =
            circle.homeX * Math.cos(angle) - circle.homeY * Math.sin(angle);
        circle.y =
            circle.homeX * Math.sin(angle) + circle.homeY * Math.cos(angle);
    });
    stepFriendOrbit(circles, bounds, elapsed, 0);
};
