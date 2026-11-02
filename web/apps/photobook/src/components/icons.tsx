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

const AppIcon = forwardRef<
    SVGSVGElement,
    SvgIconProps & { icon: IconSvgElement }
>(({ icon, ...props }, ref) => (
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

export const AddPhotosIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={ImageAdd02Icon} />,
);
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
export const AddPageIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={FileAddIcon} />,
);
export const PreviewIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={PlayIcon} />,
);
export const CloseIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={Cancel01Icon} />,
);
export const ChevronLeftIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={ArrowLeft01Icon} />,
);
export const ChevronRightIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={ArrowRight01Icon} />,
);
export const ChevronDownIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={ArrowDown01Icon} />,
);
export const EditIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={Edit02Icon} />,
);
export const DownloadIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={Download04Icon} />,
);
export const MoreIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={MoreHorizontalIcon} />,
);
export const DeleteIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={Delete02Icon} />,
);
export const ZoomInIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={SearchAddIcon} />,
);
export const ZoomOutIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={SearchMinusIcon} />,
);
export const RotateIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={RotateCcwIcon} />,
);
export const UndoIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={Undo03Icon} />,
);
export const RedoIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={Redo03Icon} />,
);
export const SuccessIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => (
        <AppIcon {...props} ref={ref} icon={CheckmarkCircle02Icon} />
    ),
);
export const InfoIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => (
        <AppIcon {...props} ref={ref} icon={InformationCircleIcon} />
    ),
);
export const WarningIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={Alert02Icon} />,
);
export const ErrorIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={AlertCircleIcon} />,
);
