"use client";

import {
    Alert02Icon,
    AlertCircleIcon,
    ArrowDown01Icon,
    ArrowLeft01Icon,
    ArrowRight01Icon,
    Cancel01Icon,
    CheckmarkCircle02Icon,
    Delete02Icon,
    Download04Icon,
    Edit02Icon,
    FileAddIcon,
    ImageAdd02Icon,
    InformationCircleIcon,
    Link01Icon,
    Menu01Icon,
    MoreHorizontalIcon,
    PlayIcon,
    Redo03Icon,
    RotateCcwIcon,
    SearchAddIcon,
    SearchMinusIcon,
    Undo03Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon, type IconSvgElement } from "@hugeicons/react";
import SvgIcon, { type SvgIconProps } from "@mui/material/SvgIcon";
import { forwardRef } from "react";

// Keep MUI sizing, colors and accessibility while rendering Hugeicons paths.
function createIcon(icon: IconSvgElement, name: string) {
    const Icon = forwardRef<SVGSVGElement, SvgIconProps>((props, ref) => (
        <SvgIcon
            {...props}
            ref={ref}
            component={HugeiconsIcon}
            icon={icon}
            strokeWidth={Number(props.strokeWidth ?? 1.8)}
            inheritViewBox
            style={{ ...props.style, fill: "none" }}
        />
    ));
    Icon.displayName = name;
    return Icon;
}

export const AddPhotosIcon = createIcon(ImageAdd02Icon, "AddPhotosIcon");
export const EditPhotoIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => (
        <SvgIcon {...props} ref={ref}>
            <g
                fill="none"
                stroke="currentColor"
                strokeWidth={1.8}
                strokeLinecap="round"
                strokeLinejoin="round"
            >
                <path d="M10.5 21H8a5 5 0 0 1-5-5V8a5 5 0 0 1 5-5h8a5 5 0 0 1 5 5v1.5" />
                <path d="m3 16 4.47-4.47a1.81 1.81 0 0 1 2.56 0L13 14.5" />
                <circle cx={16.5} cy={7.5} r={0.5} />
                <path d="m18.5 15 1.5 1.5m1.43-3.07.14.14a1.48 1.48 0 0 1 0 2.08l-4.76 4.76a2 2 0 0 1-1.42.59h-.89a.5.5 0 0 1-.5-.5v-.89a2 2 0 0 1 .59-1.42l4.76-4.76a1.48 1.48 0 0 1 2.08 0Z" />
            </g>
        </SvgIcon>
    ),
);
EditPhotoIcon.displayName = "EditPhotoIcon";
export const AddPageIcon = createIcon(FileAddIcon, "AddPageIcon");
export const PreviewIcon = createIcon(PlayIcon, "PreviewIcon");
export const CloseIcon = createIcon(Cancel01Icon, "CloseIcon");
export const ChevronLeftIcon = createIcon(ArrowLeft01Icon, "ChevronLeftIcon");
export const ChevronRightIcon = createIcon(
    ArrowRight01Icon,
    "ChevronRightIcon",
);
export const ChevronDownIcon = createIcon(ArrowDown01Icon, "ChevronDownIcon");
export const EditIcon = createIcon(Edit02Icon, "EditIcon");
export const DownloadIcon = createIcon(Download04Icon, "DownloadIcon");
export const LinkIcon = createIcon(Link01Icon, "LinkIcon");
export const MenuIcon = createIcon(Menu01Icon, "MenuIcon");
export const MoreIcon = createIcon(MoreHorizontalIcon, "MoreIcon");
export const DeleteIcon = createIcon(Delete02Icon, "DeleteIcon");
export const ZoomInIcon = createIcon(SearchAddIcon, "ZoomInIcon");
export const ZoomOutIcon = createIcon(SearchMinusIcon, "ZoomOutIcon");
export const RotateIcon = createIcon(RotateCcwIcon, "RotateIcon");
export const UndoIcon = createIcon(Undo03Icon, "UndoIcon");
export const RedoIcon = createIcon(Redo03Icon, "RedoIcon");
export const SuccessIcon = createIcon(CheckmarkCircle02Icon, "SuccessIcon");
export const InfoIcon = createIcon(InformationCircleIcon, "InfoIcon");
export const WarningIcon = createIcon(Alert02Icon, "WarningIcon");
export const ErrorIcon = createIcon(AlertCircleIcon, "ErrorIcon");
