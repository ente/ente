import {
    ChatFeedback01Icon,
    Download01Icon,
    ImageAdd02Icon,
    Share08Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import React from "react";

export interface ActionIconProps {
    size?: number;
    strokeWidth?: number;
}

const defaultSize = 24;
const defaultStrokeWidth = 1.6;

export const FeedIcon: React.FC<ActionIconProps> = ({
    size = defaultSize,
    strokeWidth = defaultStrokeWidth,
}) => (
    <HugeiconsIcon
        icon={ChatFeedback01Icon}
        size={size}
        strokeWidth={strokeWidth}
    />
);

export const DownloadIcon: React.FC<ActionIconProps> = ({
    size = defaultSize,
    strokeWidth = defaultStrokeWidth,
}) => (
    <HugeiconsIcon
        icon={Download01Icon}
        size={size}
        strokeWidth={strokeWidth}
    />
);

export const AddPhotosIcon: React.FC<ActionIconProps> = ({
    size = defaultSize,
    strokeWidth = defaultStrokeWidth,
}) => (
    <HugeiconsIcon
        icon={ImageAdd02Icon}
        size={size}
        strokeWidth={strokeWidth}
    />
);

export const ShareIcon: React.FC<ActionIconProps> = ({
    size = defaultSize,
    strokeWidth = defaultStrokeWidth,
}) => (
    <HugeiconsIcon icon={Share08Icon} size={size} strokeWidth={strokeWidth} />
);
