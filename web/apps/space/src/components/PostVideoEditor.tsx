import { VolumeHighIcon, VolumeOffIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import {
    dragVideoTrim,
    type VideoTrimHandle,
} from "components/video-trim/geometry";
import { createVideoTrimPlayback } from "components/video-trim/playback";
import React from "react";
import {
    spaceControlBackgroundHover,
    spaceSurface,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import {
    clampVideoCover,
    initialSpaceVideoEdit,
    maxSpaceVideoDuration,
    spaceVideoFrames,
    type SpacePostVideoEdit,
} from "utils/post-video";

const control = {
    alignItems: "center",
    bgcolor: spaceSurface,
    border: 0,
    borderRadius: "999px",
    color: spaceText,
    cursor: "pointer",
    display: "inline-flex",
    font: "inherit",
    fontSize: 13,
    fontWeight: 600,
    justifyContent: "center",
    minHeight: 44,
    px: "12px",
    "&:disabled": { color: "#777777", cursor: "default" },
    "&:focus-visible": { outline: "2px solid #08C225", outlineOffset: 2 },
};
const bound = (value: number, min: number, max: number) =>
    Math.max(min, Math.min(max, value));
type DragMode = VideoTrimHandle | "cover";

export const SpacePostVideoEditor: React.FC<{
    file: File;
    sourceURL: string;
    duration: number;
    edit: SpacePostVideoEdit;
    onChange: (edit: SpacePostVideoEdit) => void;
}> = ({ file, sourceURL, duration, edit, onChange }) => {
    const [mode, setMode] = React.useState<"trim" | "cover">("trim");
    const [frames, setFrames] = React.useState<string[]>([]);
    const [playing, setPlaying] = React.useState(false);
    const [previewError, setPreviewError] = React.useState<string>();
    const videoRef = React.useRef<HTMLVideoElement>(null);
    const timelineRef = React.useRef<HTMLDivElement>(null);
    const latest = React.useRef({ edit, onChange });
    latest.current = { edit, onChange };
    const playback =
        React.useRef<ReturnType<typeof createVideoTrimPlayback>>(undefined);
    const drag = React.useRef<
        | {
              mode: DragMode;
              grabOffset: number;
              edit: SpacePostVideoEdit;
              pointerID: number;
          }
        | undefined
    >(undefined);
    const minimum = Math.min(1 / 30, duration);
    const originalEdit = initialSpaceVideoEdit(duration);
    const isEdited =
        edit.start != originalEdit.start ||
        edit.end != originalEdit.end ||
        edit.coverTime != originalEdit.coverTime ||
        edit.muted != originalEdit.muted;
    const span = mode == "cover" ? edit.end - edit.start : duration;
    const visibleStart = mode == "cover" ? edit.start : 0;
    const percent = (time: number) => (100 * (time - visibleStart)) / span;

    React.useEffect(() => {
        const controller = createVideoTrimPlayback(
            videoRef.current!,
            () => latest.current.edit,
            () => setPreviewError("Couldn't play this video preview."),
        );
        playback.current = controller;
        return () => {
            controller.dispose();
            playback.current = undefined;
        };
    }, []);

    const seek = React.useCallback((time: number) => {
        playback.current?.seek(time);
    }, []);

    const togglePlayback = () => {
        setPreviewError(undefined);
        playback.current?.toggle();
    };

    React.useEffect(() => {
        seek(
            mode == "cover"
                ? latest.current.edit.coverTime
                : latest.current.edit.start,
        );
    }, [mode, seek]);

    React.useEffect(() => {
        const video = videoRef.current!;
        const pause = () => {
            if (document.hidden) video.pause();
        };
        document.addEventListener("visibilitychange", pause);
        return () => {
            video.pause();
            document.removeEventListener("visibilitychange", pause);
        };
    }, []);

    React.useEffect(() => {
        const controller = new AbortController();
        const { signal } = controller;
        const urls: string[] = [];
        const timer = window.setTimeout(() => {
            void (async () => {
                const times = Array.from(
                    { length: 8 },
                    (_, i) => visibleStart + (span * (i + 0.5)) / 8,
                );
                const frames = await spaceVideoFrames(file, times, 128, signal);
                for (const frame of frames) {
                    const canvas = document.createElement("canvas");
                    canvas.width = 80;
                    canvas.height = 64;
                    const scale = Math.max(80 / frame.width, 64 / frame.height);
                    const width = frame.width * scale;
                    const height = frame.height * scale;
                    canvas
                        .getContext("2d")!
                        .drawImage(
                            frame,
                            (80 - width) / 2,
                            (64 - height) / 2,
                            width,
                            height,
                        );
                    urls.push(canvas.toDataURL("image/jpeg", 0.65));
                }
                if (!signal.aborted) setFrames(urls);
            })().catch(() => {
                if (!signal.aborted) setFrames([]);
            });
        }, 120);
        return () => {
            controller.abort();
            window.clearTimeout(timer);
        };
    }, [file, visibleStart, span]);

    const changeBoundary = (boundary: "start" | "end", value: number) => {
        if (!Number.isFinite(value)) return;
        const next = clampVideoCover({
            ...edit,
            ...dragVideoTrim(
                edit,
                boundary,
                value,
                duration,
                maxSpaceVideoDuration,
            ),
        });
        onChange(next);
        seek(
            boundary == "start"
                ? next.start
                : Math.max(next.start, next.end - minimum),
        );
    };

    const updateDrag = (clientX: number) => {
        const gesture = drag.current;
        const rect = timelineRef.current?.getBoundingClientRect();
        if (!gesture || !rect) return;
        let next = { ...gesture.edit };
        if (gesture.mode == "cover")
            next.coverTime =
                visibleStart +
                bound((clientX - rect.left) / rect.width, 0, 1) * span;
        else {
            const position =
                ((clientX - rect.left) / rect.width) * duration -
                gesture.grabOffset;
            Object.assign(
                next,
                dragVideoTrim(
                    next,
                    gesture.mode,
                    position,
                    duration,
                    maxSpaceVideoDuration,
                ),
            );
        }
        next = clampVideoCover(next);
        const previous = latest.current.edit;
        const changed =
            next.start != previous.start ||
            next.end != previous.end ||
            next.coverTime != previous.coverTime;
        if (changed) {
            latest.current.edit = next;
            latest.current.onChange(next);
        }
        if (changed || gesture.mode == "cover")
            seek(
                gesture.mode == "cover"
                    ? next.coverTime
                    : gesture.mode == "end"
                      ? Math.max(next.start, next.end - minimum)
                      : next.start,
            );
    };

    const startDrag = (event: React.PointerEvent<HTMLDivElement>) => {
        if (!event.isPrimary || event.button != 0 || drag.current) return;
        const rect = event.currentTarget.getBoundingClientRect();
        const x = event.clientX - rect.left;
        const left = (percent(edit.start) / 100) * rect.width;
        const right = (percent(edit.end) / 100) * rect.width;
        const handle =
            Math.min(Math.abs(x - left), Math.abs(x - right)) <=
            Math.min(22, (right - left) / 3);
        const action =
            mode == "cover"
                ? "cover"
                : handle
                  ? Math.abs(x - left) <= Math.abs(x - right)
                      ? "start"
                      : "end"
                  : x > left && x < right
                    ? "move"
                    : undefined;
        if (!action) return;
        event.preventDefault();
        drag.current = {
            mode: action,
            grabOffset:
                visibleStart +
                (x / rect.width) * span -
                (action == "end" ? edit.end : edit.start),
            edit,
            pointerID: event.pointerId,
        };
        event.currentTarget.setPointerCapture(event.pointerId);
        videoRef.current?.pause();
        updateDrag(event.clientX);
    };

    const stopDrag = () => {
        drag.current = undefined;
    };

    return (
        <Box
            sx={{
                display: "flex",
                flexDirection: "column",
                flex: 1,
                minHeight: 0,
                width: "100%",
            }}
        >
            <Box
                sx={{
                    flex: 1,
                    minHeight: 0,
                    display: "flex",
                    justifyContent: "center",
                    position: "relative",
                    px: "24px",
                    py: "20px",
                }}
            >
                <video
                    aria-label={playing ? "Pause video" : "Play video"}
                    role="button"
                    tabIndex={0}
                    ref={videoRef}
                    src={sourceURL}
                    playsInline
                    muted={edit.muted}
                    style={{
                        width: "100%",
                        height: "100%",
                        objectFit: "contain",
                        cursor: "pointer",
                    }}
                    onClick={togglePlayback}
                    onKeyDown={(event) => {
                        if (event.key == " " || event.key == "Enter") {
                            event.preventDefault();
                            togglePlayback();
                        }
                    }}
                    onPlay={() => setPlaying(true)}
                    onPause={() => setPlaying(false)}
                    onEnded={() => setPlaying(false)}
                    onError={() =>
                        setPreviewError("Couldn't play this video preview.")
                    }
                />
                {!playing && (
                    <Box
                        component="button"
                        type="button"
                        aria-label="Play video"
                        onClick={() => {
                            videoRef.current!.focus({ preventScroll: true });
                            togglePlayback();
                        }}
                        sx={{
                            position: "absolute",
                            top: "50%",
                            left: "50%",
                            transform: "translate(-50%, -50%)",
                            border: 0,
                            borderRadius: "50%",
                            bgcolor: "rgba(0, 0, 0, 0.45)",
                            color: "#FFFFFF",
                            width: 44,
                            height: 44,
                            p: "10px",
                            cursor: "pointer",
                            "&:focus-visible": {
                                outline: "2px solid #08C225",
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <svg
                            width={24}
                            height={24}
                            viewBox="0 0 24 24"
                            fill="currentColor"
                            aria-hidden
                            style={{ display: "block" }}
                        >
                            <path d="M6 3v18l15-9z" />
                        </svg>
                    </Box>
                )}
            </Box>
            <Box
                sx={{
                    width: "100%",
                    maxWidth: 414,
                    boxSizing: "border-box",
                    px: "12px",
                    alignSelf: "center",
                    flexShrink: 0,
                    display: "flex",
                    flexDirection: "column",
                    gap: "16px",
                }}
            >
                {previewError && (
                    <Box role="alert" sx={{ color: "#FF8A8A", fontSize: 13 }}>
                        {previewError}
                    </Box>
                )}
                <Box sx={{ mx: "10px" }}>
                    <Box
                        ref={timelineRef}
                        onPointerDown={startDrag}
                        onPointerMove={(event) => {
                            if (drag.current?.pointerID == event.pointerId)
                                updateDrag(event.clientX);
                        }}
                        onPointerUp={(event) => {
                            if (drag.current?.pointerID != event.pointerId)
                                return;
                            updateDrag(event.clientX);
                            stopDrag();
                            if (
                                event.currentTarget.hasPointerCapture(
                                    event.pointerId,
                                )
                            )
                                event.currentTarget.releasePointerCapture(
                                    event.pointerId,
                                );
                        }}
                        onPointerCancel={stopDrag}
                        onLostPointerCapture={stopDrag}
                        sx={{
                            height: 64,
                            position: "relative",
                            bgcolor: spaceSurface,
                            borderRadius: "8px",
                            touchAction: "none",
                            userSelect: "none",
                        }}
                    >
                        <Box
                            sx={{
                                display: "flex",
                                width: "100%",
                                height: "100%",
                                overflow: "hidden",
                                borderRadius: "8px",
                                pointerEvents: "none",
                                "&::after":
                                    mode == "trim"
                                        ? {
                                              content: '""',
                                              position: "absolute",
                                              inset: 0,
                                              borderRadius: "8px",
                                              background: `linear-gradient(to right, #0008 ${bound(percent(edit.start), 0, 100)}%, transparent ${bound(percent(edit.start), 0, 100)}%, transparent ${bound(percent(edit.end), 0, 100)}%, #0008 ${bound(percent(edit.end), 0, 100)}%)`,
                                          }
                                        : undefined,
                            }}
                        >
                            {frames.map((url, index) => (
                                <img
                                    key={index}
                                    src={url}
                                    alt=""
                                    draggable={false}
                                    style={{
                                        width: "12.5%",
                                        objectFit: "cover",
                                    }}
                                />
                            ))}
                        </Box>
                        {mode == "trim" && (
                            <Box
                                sx={{
                                    position: "absolute",
                                    insetBlock: 0,
                                    left: `${bound(percent(edit.start), 0, 100)}%`,
                                    right: `${100 - bound(percent(edit.end), 0, 100)}%`,
                                    borderBlock: "3px solid white",
                                    boxSizing: "border-box",
                                    cursor: "grab",
                                }}
                            />
                        )}
                        {(mode == "trim"
                            ? (["start", "end"] as const)
                            : (["coverTime"] as const)
                        ).map((boundary) => (
                            <Box
                                key={boundary}
                                role="slider"
                                tabIndex={0}
                                aria-label={
                                    boundary == "coverTime"
                                        ? "Cover frame"
                                        : boundary == "start"
                                          ? "Trim start"
                                          : "Trim end"
                                }
                                aria-valuemin={
                                    boundary == "end"
                                        ? edit.start + minimum
                                        : boundary == "start"
                                          ? Math.max(
                                                0,
                                                edit.end -
                                                    maxSpaceVideoDuration,
                                            )
                                          : edit.start
                                }
                                aria-valuemax={
                                    boundary == "start"
                                        ? edit.end - minimum
                                        : boundary == "end"
                                          ? Math.min(
                                                duration,
                                                edit.start +
                                                    maxSpaceVideoDuration,
                                            )
                                          : edit.end - 0.001
                                }
                                aria-valuenow={edit[boundary]}
                                aria-valuetext={`${edit[boundary].toFixed(2)} seconds`}
                                onKeyDown={(event) => {
                                    if (
                                        ![
                                            "ArrowLeft",
                                            "ArrowRight",
                                            "Home",
                                            "End",
                                        ].includes(event.key)
                                    )
                                        return;
                                    event.preventDefault();
                                    event.stopPropagation();
                                    const value =
                                        event.key == "Home"
                                            ? 0
                                            : event.key == "End"
                                              ? duration
                                              : edit[boundary] +
                                                (event.key == "ArrowLeft"
                                                    ? -1
                                                    : 1) *
                                                    (event.shiftKey ? 1 : 0.1);
                                    if (boundary == "coverTime") {
                                        const next = clampVideoCover({
                                            ...edit,
                                            coverTime: value,
                                        });
                                        onChange(next);
                                        seek(next.coverTime);
                                    } else changeBoundary(boundary, value);
                                }}
                                sx={{
                                    position: "absolute",
                                    top: -4,
                                    bottom: -4,
                                    width: 44,
                                    left: `calc(${bound(percent(edit[boundary]), 0, 100)}% - 22px)`,
                                    cursor: "ew-resize",
                                    display: "flex",
                                    justifyContent: "center",
                                    "&:focus-visible": {
                                        outline: "2px solid #08C225",
                                    },
                                }}
                            >
                                <Box
                                    sx={{
                                        width: mode == "trim" ? 14 : 4,
                                        bgcolor: "white",
                                        borderRadius: "4px",
                                        border: "1px solid #777",
                                        boxSizing: "border-box",
                                    }}
                                />
                            </Box>
                        ))}
                    </Box>
                </Box>
                <Box
                    sx={{
                        display: "grid",
                        gridTemplateColumns: "44px minmax(0, 1fr) auto",
                        gap: "6px",
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        sx={{ ...control, p: 0 }}
                        aria-label={edit.muted ? "Sound off" : "Sound on"}
                        title={edit.muted ? "Turn sound on" : "Turn sound off"}
                        aria-pressed={!edit.muted}
                        onClick={() =>
                            onChange({ ...edit, muted: !edit.muted })
                        }
                    >
                        <HugeiconsIcon
                            icon={edit.muted ? VolumeOffIcon : VolumeHighIcon}
                            size={20}
                            strokeWidth={1.8}
                        />
                    </Box>
                    <Box
                        role="group"
                        aria-label="Video editing mode"
                        sx={{
                            position: "relative",
                            display: "flex",
                            bgcolor: spaceSurface,
                            borderRadius: "999px",
                            px: "4px",
                        }}
                    >
                        <Box
                            aria-hidden="true"
                            sx={{
                                position: "absolute",
                                top: 4,
                                bottom: 4,
                                left: 4,
                                width: "calc((100% - 8px) / 2)",
                                bgcolor: spaceControlBackgroundHover,
                                borderRadius: "999px",
                                pointerEvents: "none",
                                transform: `translateX(${mode == "trim" ? 0 : 100}%)`,
                                transition: "transform 200ms ease",
                                "@media (prefers-reduced-motion: reduce)": {
                                    transition: "none",
                                },
                            }}
                        />
                        {(["trim", "cover"] as const).map((value) => (
                            <Box
                                key={value}
                                component="button"
                                type="button"
                                aria-pressed={mode == value}
                                onClick={() => setMode(value)}
                                sx={{
                                    ...control,
                                    position: "relative",
                                    flex: 1,
                                    minWidth: 0,
                                    p: 0,
                                    bgcolor: "transparent",
                                    color:
                                        mode == value
                                            ? "#FFFFFF"
                                            : spaceTextMuted,
                                }}
                            >
                                {value == "trim" ? "Trim" : "Cover"}
                            </Box>
                        ))}
                    </Box>
                    <Box
                        component="button"
                        type="button"
                        title="Reset edits"
                        disabled={!isEdited}
                        sx={{ ...control, px: "16px", py: 0 }}
                        onClick={() => {
                            onChange(originalEdit);
                            seek(0);
                        }}
                    >
                        Reset
                    </Box>
                </Box>
            </Box>
        </Box>
    );
};
