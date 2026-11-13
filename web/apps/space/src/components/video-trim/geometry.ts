export type VideoTrimHandle = "start" | "end" | "move";

interface VideoTrimRange {
    start: number;
    end: number;
}

const bound = (value: number, min: number, max: number) =>
    Math.max(min, Math.min(max, value));

export const dragVideoTrim = (
    range: VideoTrimRange,
    handle: VideoTrimHandle,
    position: number,
    duration: number,
    maximum: number,
): VideoTrimRange => {
    const minimum = Math.min(1 / 30, duration);
    if (handle == "start")
        return {
            start: bound(
                position,
                Math.max(0, range.end - maximum),
                range.end - minimum,
            ),
            end: range.end,
        };
    if (handle == "end")
        return {
            start: range.start,
            end: bound(
                position,
                range.start + minimum,
                Math.min(duration, range.start + maximum),
            ),
        };
    const length = range.end - range.start;
    const start = bound(position, 0, duration - length);
    return { start, end: start + length };
};
