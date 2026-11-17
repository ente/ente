export interface FriendOrbitCircle {
    id: string;
    isSuggestion?: boolean;
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
export const friendOrbitSuggestionGap = 56;

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
        const homeX = circle.homeX + driftX;
        const homeY = circle.homeY + driftY;
        const x = homeX * cos - homeY * sin;
        const y = homeX * sin + homeY * cos;
        circle.vx = (circle.vx + (x - circle.x) * 0.018 * frame) * damping;
        circle.vy = (circle.vy + (y - circle.y) * 0.018 * frame) * damping;
        circle.x += circle.vx * frame;
        circle.y += circle.vy * frame;
    });

    for (let pass = 0; pass < 32; pass++) {
        let maxPush = 0;
        for (let i = 0; i < circles.length; i++) {
            const first = circles[i]!;
            for (let j = i + 1; j < circles.length; j++) {
                const second = circles[j]!;
                const dx = second.x - first.x;
                const dy = second.y - first.y;
                const gap =
                    Boolean(first.isSuggestion) !== Boolean(second.isSuggestion)
                        ? friendOrbitSuggestionGap / bounds.scale
                        : 10;
                const separation = (first.size + second.size) / 2 + gap;
                if (Math.abs(dx) >= separation || Math.abs(dy) >= separation)
                    continue;
                const distance = Math.hypot(dx, dy);
                if (distance >= separation) continue;
                const nx = distance < 0.001 ? Math.cos(i + j) : dx / distance;
                const ny = distance < 0.001 ? Math.sin(i + j) : dy / distance;
                const push = separation - distance;
                maxPush = Math.max(maxPush, push);
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
            const x = Math.max(
                -halfWidth + radius,
                Math.min(halfWidth - radius, circle.x),
            );
            const y = Math.max(
                -halfHeight + radius,
                Math.min(halfHeight - radius, circle.y),
            );
            maxPush = Math.max(
                maxPush,
                Math.abs(x - circle.x),
                Math.abs(y - circle.y),
            );
            circle.x = x;
            circle.y = y;
        });
        if (maxPush * bounds.scale < 0.1) break;
    }
};

export const arrangeFriendOrbit = (
    circles: FriendOrbitCircle[],
    bounds: FriendOrbitBounds,
    elapsed: number,
) => {
    circles.forEach((circle, index) => {
        const initial = createFriendOrbitCircle(circle.id, index);
        Object.assign(circle, initial, { size: circle.size });
    });
    const main = circles.filter((circle) => !circle.isSuggestion);
    const group = main.length ? main : circles;
    for (let frame = 0; frame < 90; frame++) {
        stepFriendOrbit(group, bounds, 0, 16.667, undefined, true);
    }
    if (main.length && main.length < circles.length) {
        const suggestions = circles.filter((circle) => circle.isSuggestion);
        const vertical = bounds.height >= bounds.width;
        const edge = main.reduce(
            (max, friend) =>
                Math.max(max, Math.hypot(friend.x, friend.y) + friend.size / 2),
            0,
        );
        suggestions.forEach((circle, index) => {
            const side = index % 2;
            const countOnSide = Math.ceil((suggestions.length - side) / 2);
            const across =
                (Math.floor(index / 2) - (countOnSide - 1) / 2) *
                (circle.size + 10);
            const distance =
                edge +
                circle.size / 2 +
                friendOrbitSuggestionGap / bounds.scale;
            const along = side ? distance : -distance;
            circle.x = vertical ? across : along;
            circle.y = vertical ? along : across;
        });
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
