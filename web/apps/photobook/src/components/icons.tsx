import {
    Alert02Icon,
    AlertCircleIcon,
    ArrowAllDirectionIcon,
    ArrowDown01Icon,
    ArrowLeft01Icon,
    ArrowRight01Icon,
    ArrowRight02Icon,
    BookOpen01Icon,
    Cancel01Icon,
    CheckmarkCircle02Icon,
    CloudUploadIcon,
    Delete02Icon,
    Download04Icon,
    Edit02Icon,
    FileAddIcon,
    ImageAdd02Icon,
    InformationCircleIcon,
    Location01Icon,
    MinusSignIcon,
    MoreHorizontalIcon,
    PanelLeftCloseIcon,
    PanelLeftOpenIcon,
    PlayIcon,
    PlusSignIcon,
    Redo03Icon,
    RotateCcwIcon,
    RotateCwIcon,
    TextFontIcon,
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
export const BookIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={BookOpen01Icon} />,
);
export const AddPageIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={FileAddIcon} />,
);
export const PreviewIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={PlayIcon} />,
);
export const DownloadIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={Download04Icon} />,
);
export const UploadIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={CloudUploadIcon} />,
);

export const ArrowRightIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={ArrowRight02Icon} />,
);
export const LocationIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={Location01Icon} />,
);
export const CloseIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={Cancel01Icon} />,
);
export const CloseSidebarIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={PanelLeftCloseIcon} />,
);
export const OpenSidebarIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={PanelLeftOpenIcon} />,
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
export const TitleIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={TextFontIcon} />,
);
export const MoreIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={MoreHorizontalIcon} />,
);
export const DeleteIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={Delete02Icon} />,
);
export const PanIcon = forwardRef<SVGSVGElement, SvgIconProps>((props, ref) => (
    <AppIcon {...props} ref={ref} icon={ArrowAllDirectionIcon} />
));
export const ZoomInIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={PlusSignIcon} />,
);
export const ZoomOutIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={MinusSignIcon} />,
);
export const RotatePhotoIcon = forwardRef<SVGSVGElement, SvgIconProps>(
    (props, ref) => <AppIcon {...props} ref={ref} icon={RotateCwIcon} />,
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
