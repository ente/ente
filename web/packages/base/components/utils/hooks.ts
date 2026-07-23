import { useMediaQuery, useTheme } from "@mui/material";
import { useCallback, useEffect, useEffectEvent, useState } from "react";

/**
 * Return true if the screen width is classified as a small size. This is often
 * treated as an (rather arbitrary) cutoff for "mobile" sized screens.
 *
 * We use the MUI "sm" (small, 600px) breakpoint as the cutoff. This hook will
 * return true if the size of the window's width is less than 600px.
 */
export const useIsSmallWidth = () =>
    useMediaQuery(useTheme().breakpoints.down("sm"));

/**
 * Heuristic "isMobileOrTablet"-ish check using a pointer media query.
 *
 * The absence of fine-resolution pointing device can be taken a quick and proxy
 * for detecting if the user is using a mobile or tablet.
 *
 * This is of course not going to work in all scenarios (e.g. someone connecting
 * their mice to their tablet), but ad-hoc user agent checks are not problem
 * free either. This media query should be accurate enough for cases where false
 * positives will degrade gracefully.
 *
 * See: https://github.com/mui/mui-x/issues/10039
 */
export const useIsTouchscreen = () =>
    useMediaQuery("(hover: none) and (pointer: coarse)", { noSsr: true });

/**
 * A hook that manages a transient "copied" state.
 *
 * @param text The text to copy.
 *
 * @returns a tuple containing a boolean {@link copied} indicating if a copy has
 * just successfully happened, and a function {@link onCopy} to trigger the
 * copy.
 */
export const useClipboardCopy = (
    text: string,
): [copied: boolean, onCopy: () => void] => {
    const [copied, setCopied] = useState(false);

    const handleCopyLink = useCallback(() => {
        void navigator.clipboard.writeText(text).then(() => {
            setCopied(true);
            setTimeout(() => setCopied(false), 1000);
        });
    }, [text]);

    return [copied, handleCopyLink];
};

/**
 * A hook that runs a callback at a specified interval.
 *
 * @param callback The function to call on each interval tick.
 * @param delay The interval in milliseconds, or null to pause the interval.
 */
export const useInterval = (
    callback: () => void,
    delay: number | null,
): void => {
    const onTick = useEffectEvent(callback);

    useEffect(() => {
        if (delay === null) return;

        const id = setInterval(onTick, delay);
        return () => clearInterval(id);
    }, [delay]);
};
