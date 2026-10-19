export const stepFriendSheetSpring = (
    position: number,
    velocity: number,
    target: number,
    elapsedMs: number,
) => {
    const time = elapsedMs / 1000;
    const displacement = position - target;
    const coefficient = velocity + 24 * displacement;
    const decay = Math.exp(-24 * time);
    return {
        position: target + (displacement + coefficient * time) * decay,
        velocity: (velocity - 24 * coefficient * time) * decay,
    };
};

export const friendSheetSnap = (
    position: number,
    velocity: number,
    collapsed: number,
    height: number,
) => {
    const projected = position + velocity * 0.18;
    if (projected < collapsed * 0.65) return "expanded";
    if (projected > collapsed + (height - collapsed) * 0.35) return "closed";
    return "collapsed";
};
