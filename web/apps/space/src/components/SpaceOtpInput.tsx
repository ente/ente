import { Box } from "@mui/material";
import React from "react";
import { sanitizeSpaceOTP, spaceOTPCodeLength } from "utils/spaceOtp";

const green = "#08C225";
const activeFill = "rgba(8, 194, 37, 0.08)";
const emptyStroke = "#EDF0FF";

interface SpaceOtpInputProps {
    ariaLabel: string;
    onChange: (value: string) => void;
    value: string;
}

export const SpaceOtpInput = React.forwardRef<
    HTMLInputElement,
    SpaceOtpInputProps
>(({ ariaLabel, onChange, value }, ref) => {
    const [activeIndex, setActiveIndex] = React.useState<number | undefined>(
        value.length < spaceOTPCodeLength ? value.length : undefined,
    );
    const digits = value
        .padEnd(spaceOTPCodeLength, " ")
        .slice(0, spaceOTPCodeLength)
        .split("")
        .map((digit) => (digit == " " ? "" : digit));

    React.useEffect(() => {
        if (value.length < spaceOTPCodeLength && activeIndex == undefined) {
            setActiveIndex(value.length);
            return;
        }

        if (activeIndex != undefined && activeIndex > value.length) {
            setActiveIndex(
                value.length < spaceOTPCodeLength ? value.length : undefined,
            );
        }
    }, [activeIndex, value.length]);

    const nextActiveIndex = (index: number) =>
        index < spaceOTPCodeLength ? index : undefined;

    const replaceFromActiveIndex = (inputDigits: string) => {
        const replacementDigits = sanitizeSpaceOTP(inputDigits);
        if (!replacementDigits) return;

        if (replacementDigits.length == spaceOTPCodeLength) {
            onChange(replacementDigits);
            setActiveIndex(undefined);
            return;
        }

        const startIndex =
            activeIndex ??
            (value.length < spaceOTPCodeLength ? value.length : undefined);
        if (startIndex == undefined) return;

        const nextDigits = value.split("");
        const clampedStartIndex = Math.min(startIndex, value.length);

        for (let index = 0; index < replacementDigits.length; index++) {
            const targetIndex = clampedStartIndex + index;
            if (targetIndex >= spaceOTPCodeLength) break;
            nextDigits[targetIndex] = replacementDigits[index]!;
        }

        const nextValue = nextDigits.join("").slice(0, spaceOTPCodeLength);
        onChange(nextValue);
        setActiveIndex(
            nextActiveIndex(
                Math.min(
                    clampedStartIndex + replacementDigits.length,
                    nextValue.length,
                ),
            ),
        );
    };

    const removeAtIndex = (index: number) => {
        if (index < 0 || index >= value.length) return;

        const nextValue = value.slice(0, index) + value.slice(index + 1);
        onChange(nextValue);
        setActiveIndex(Math.min(index, nextValue.length));
    };

    const handleBackspace = () => {
        if (activeIndex == undefined) {
            removeAtIndex(value.length - 1);
        } else if (activeIndex < value.length) {
            removeAtIndex(activeIndex);
        } else {
            removeAtIndex(activeIndex - 1);
        }
    };

    const selectCell = (input: HTMLInputElement, clientX: number) => {
        const { left, width } = input.getBoundingClientRect();
        const cellIndex = Math.max(
            0,
            Math.min(
                spaceOTPCodeLength - 1,
                Math.floor(((clientX - left) / width) * spaceOTPCodeLength),
            ),
        );

        setActiveIndex(Math.min(cellIndex, value.length));
    };

    const handleBeforeInput = (event: React.InputEvent<HTMLInputElement>) => {
        const inputEvent = event.nativeEvent;
        if (!inputEvent.data) return;

        event.preventDefault();
        replaceFromActiveIndex(inputEvent.data);
    };

    const handleChange = (event: React.ChangeEvent<HTMLInputElement>) => {
        const nextValue = sanitizeSpaceOTP(event.target.value);
        if (nextValue == value) return;

        onChange(nextValue);
        setActiveIndex(
            nextValue.length < spaceOTPCodeLength
                ? nextValue.length
                : undefined,
        );
    };

    const handleKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
        if (event.metaKey || event.ctrlKey || event.altKey) return;

        if (/^\d$/.test(event.key)) {
            event.preventDefault();
            replaceFromActiveIndex(event.key);
            return;
        }

        switch (event.key) {
            case "Backspace":
                event.preventDefault();
                handleBackspace();
                break;
            case "Delete":
                event.preventDefault();
                if (activeIndex != undefined) removeAtIndex(activeIndex);
                break;
            case "ArrowLeft":
                event.preventDefault();
                setActiveIndex(
                    Math.max(
                        0,
                        activeIndex == undefined
                            ? value.length - 1
                            : activeIndex - 1,
                    ),
                );
                break;
            case "ArrowRight":
                event.preventDefault();
                setActiveIndex(
                    activeIndex == undefined
                        ? undefined
                        : nextActiveIndex(activeIndex + 1),
                );
                break;
        }
    };

    return (
        <Box sx={{ height: 52, position: "relative", width: "100%" }}>
            <Box
                component="input"
                ref={ref}
                aria-label={ariaLabel}
                autoComplete="one-time-code"
                inputMode="numeric"
                maxLength={spaceOTPCodeLength}
                onBeforeInput={handleBeforeInput}
                onChange={handleChange}
                onClick={(event) =>
                    selectCell(event.currentTarget, event.clientX)
                }
                onFocus={() =>
                    setActiveIndex(
                        value.length < spaceOTPCodeLength
                            ? value.length
                            : undefined,
                    )
                }
                onKeyDown={handleKeyDown}
                onPaste={(event) => {
                    event.preventDefault();
                    const nextValue = sanitizeSpaceOTP(
                        event.clipboardData.getData("text"),
                    );
                    if (nextValue.length == spaceOTPCodeLength) {
                        onChange(nextValue);
                        setActiveIndex(undefined);
                    } else {
                        replaceFromActiveIndex(nextValue);
                    }
                }}
                pattern="[0-9]*"
                type="text"
                value={value}
                sx={{
                    WebkitTextFillColor: "transparent",
                    bgcolor: "transparent",
                    border: 0,
                    caretColor: "transparent",
                    color: "transparent",
                    fontSize: 16,
                    height: "100%",
                    inset: 0,
                    opacity: 0,
                    outline: 0,
                    p: 0,
                    position: "absolute",
                    width: "100%",
                    zIndex: 1,
                }}
            />
            <Box
                aria-hidden
                sx={{
                    display: "flex",
                    gap: "6px",
                    height: "100%",
                    justifyContent: "stretch",
                    width: "100%",
                }}
            >
                {digits.map((digit, index) => {
                    const typed = digit.length > 0;
                    const active = activeIndex == index;

                    return (
                        <Box
                            key={index}
                            sx={{
                                alignItems: "center",
                                bgcolor: active ? activeFill : "white",
                                border:
                                    typed || active
                                        ? `2px solid ${green}`
                                        : `1px solid ${emptyStroke}`,
                                borderRadius: "20px",
                                color: green,
                                display: "flex",
                                flex: "1 1 0",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 20,
                                fontWeight: 700,
                                height: 52,
                                justifyContent: "center",
                                lineHeight: "17px",
                                minWidth: 0,
                                userSelect: "none",
                            }}
                        >
                            {digit}
                        </Box>
                    );
                })}
            </Box>
        </Box>
    );
});
