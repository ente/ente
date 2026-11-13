export const photoDotStep = 11;

export const paintStretchingDot = (
    root: HTMLElement,
    position: number,
    count: number,
) => {
    const dot = root.querySelector<HTMLElement>(
        "[data-space-photo-dots-indicator]",
    );
    if (!dot) return;
    const p = Math.min(count - 1, Math.max(0, position));
    const from = Math.min(Math.floor(p), count - 2);
    const head =
        (from + Math.min(1, Math.max(0, (p - from) * 2))) * photoDotStep;
    const tail =
        (from + Math.min(1, Math.max(0, (p - from) * 2 - 1))) * photoDotStep;
    dot.style.transform = `translate(${tail - 0.5}px, -50%)`;
    dot.style.width = `${head - tail + 6}px`;
};
