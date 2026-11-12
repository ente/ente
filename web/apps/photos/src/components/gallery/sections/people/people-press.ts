// A hold selects people; moving/scrolling must never turn into a row click.
export const createPeoplePress = (onHold: () => void) => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    let origin: { x: number; y: number } | undefined;
    let suppressClick = false;
    const end = () => {
        clearTimeout(timer);
        timer = undefined;
        origin = undefined;
    };
    const cancel = () => {
        if (origin) suppressClick = true;
        end();
    };
    return {
        start: (x: number, y: number) => {
            end();
            suppressClick = false;
            origin = { x, y };
            timer = setTimeout(() => {
                timer = undefined;
                suppressClick = true;
                onHold();
            }, 450);
        },
        move: (x: number, y: number) => {
            if (origin && Math.hypot(x - origin.x, y - origin.y) > 8) cancel();
        },
        end,
        cancel,
        consumeClick: () => {
            const suppressed = suppressClick;
            suppressClick = false;
            return suppressed;
        },
    };
};
