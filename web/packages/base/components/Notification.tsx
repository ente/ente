import CloseIcon from "@mui/icons-material/Close";
import InfoIcon from "@mui/icons-material/InfoOutlined";
import {
    IconButton,
    Snackbar,
    Stack,
    Typography,
    type ButtonProps,
    type SxProps,
    type Theme,
} from "@mui/material";
import { EllipsizedTypography } from "ente-base/components/Typography";
import { RippleDisabledButton } from "ente-base/components/mui/FocusVisibleButton";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import type {} from "ente-base/components/utils/mui-theme";
import { isSxArray } from "ente-base/components/utils/sx";
import React from "react";

/**
 * Customize the contents of an {@link Notification}.
 */
export interface NotificationAttributes {
    /**
     * If set, then the caption is shown first, then the title.
     *
     * Default is to show the title first, then the caption.
     */
    captionFirst?: boolean;
    /**
     * The color of the notification.
     */
    color: ButtonProps["color"];
    /**
     * Optional override to the default InfoIcon shown at the leading edge of
     * the notification.
     *
     * Default: InfoIcon
     */
    startIcon?: React.ReactNode;
    /**
     * The primary textual content of the notification.
     */
    title: React.ReactNode;
    /**
     * The secondary textual content of the notification.
     *
     * It will be ellipsized if it does not fit into a single line.
     */
    caption?: React.ReactNode;
    /**
     * Callback invoked (if provided) when the user clicks on the notification
     * (anywhere except the close button).
     *
     * The notification is closed when this happens, unless the
     * {@link keepOpenOnClick} property is set on the notification instance.
     */
    onClick?: () => void;
    /**
     * Optional override to the default CloseIcon shown at the trailing edge of
     * the notification.
     *
     * Unlike {@link startIcon} which is not interactable, setting this replaces
     * the close button with a icon button showing the given {@link endIcon},
     * and on clicking that icon {@link onClick} would be called instead of
     * {@link onClose} (which would've been called on clicking the default close
     * button in this position).
     */
    endIcon?: React.ReactNode;
    /**
     * Optional handler when {@link endIcon} is clicked.
     *
     * If not provided, clicks on the end icon behave the same as clicking the
     * notification body.
     */
    onEndIconClick?: () => void;
}

type NotificationProps = ModalVisibilityProps & {
    /**
     * Attributes that customize the contents of the notification, and the
     * actions that happen on clicking it.
     */
    attributes: NotificationAttributes | undefined;
    /**
     * If `true`, then the notification is not closed when it is clicked, and
     * should be closed by pressing the close icon button it contains.
     */
    keepOpenOnClick?: boolean;
    /**
     * Horizontal positioning of the notification.
     *
     * Default: "right".
     */
    horizontal?: "left" | "right";
    /**
     * Vertical positioning of the notification.
     *
     * Default: "bottom".
     */
    vertical?: "top" | "bottom";
    /**
     * Optional time in milliseconds after which the notification closes.
     */
    autoHideDuration?: number;
    /**
     * sx props to customize the appearance of the underlying MUI
     * {@link Snackbar}.
     */
    sx?: SxProps<Theme>;
};

/**
 * A small notification popup shown on some edge of the screen to notify the
 * user of some asynchronous update or error.
 *
 * In Material UI terms, this is a custom "Snackbar".
 *
 * A single Notification component can be shared by multiple sources of
 * notifications (which means that there can't be multiple of them outstanding
 * at the same time from the same source). The source can customize the actual
 * contents and appearance of this notification by providing appropriate
 * {@link NotificationAttributes}.
 */
export const Notification: React.FC<NotificationProps> = ({
    open,
    onClose,
    horizontal,
    vertical,
    autoHideDuration,
    sx,
    attributes,
    keepOpenOnClick,
}) => {
    if (!attributes) return <></>;

    const {
        captionFirst,
        color,
        startIcon,
        title,
        caption,
        endIcon,
        onClick,
        onEndIconClick,
    } = attributes;

    const handleClose: React.MouseEventHandler = (event) => {
        onClose();
        event.stopPropagation();
    };

    const handleClick = () => {
        onClick?.();
        if (!keepOpenOnClick) onClose();
    };

    const handleEndIconClick: React.MouseEventHandler = (event) => {
        event.stopPropagation();
        if (onEndIconClick) {
            onEndIconClick();
        } else {
            handleClick();
        }
    };

    return (
        <Snackbar
            open={open}
            autoHideDuration={autoHideDuration}
            onClose={(_, reason) => {
                if (reason === "timeout") onClose();
            }}
            anchorOrigin={{
                horizontal: horizontal ?? "right",
                vertical: vertical ?? "bottom",
            }}
            sx={[
                (theme) => ({
                    width: "min(320px, 100vw)",
                    backgroundColor:
                        color && color != "inherit"
                            ? `${color}.main`
                            : "transparent",
                    boxShadow: theme.vars.palette.boxShadow.menu,
                }),
                ...(sx ? (isSxArray(sx) ? sx : [sx]) : []),
            ]}
        >
            <RippleDisabledButton
                color={color}
                onClick={handleClick}
                sx={{
                    flex: "1",
                    padding: "12px 8px 12px 14px",
                    borderRadius: "8px",
                }}
            >
                <Stack
                    direction="row"
                    sx={{
                        gap: 2,
                        alignItems: "center",
                        // Necessary to get the ellipsizing to work.
                        width: "100%",
                    }}
                >
                    <Stack sx={{ svg: { fontSize: "36px" } }}>
                        {startIcon ?? <InfoIcon />}
                    </Stack>

                    <Stack
                        sx={{
                            flex: 1,
                            gap: 0.5,
                            // Undo the center alignment done by the button.
                            textAlign: "left",
                            // This is necessary to trigger the ellipsizing of the
                            // text in children.
                            overflow: "hidden",
                        }}
                    >
                        {captionFirst ? (
                            <>
                                {caption && (
                                    <EllipsizedTypography variant="small">
                                        {caption}
                                    </EllipsizedTypography>
                                )}
                                <Typography sx={{ fontWeight: "medium" }}>
                                    {title}
                                </Typography>
                            </>
                        ) : (
                            <>
                                <Typography sx={{ fontWeight: "medium" }}>
                                    {title}
                                </Typography>
                                {caption && (
                                    <EllipsizedTypography variant="small">
                                        {caption}
                                    </EllipsizedTypography>
                                )}
                            </>
                        )}
                    </Stack>

                    {endIcon ? (
                        <IconButton
                            component="div"
                            onClick={handleEndIconClick}
                            sx={{ fontSize: "36px", bgcolor: "fill.faint" }}
                        >
                            {endIcon}
                        </IconButton>
                    ) : (
                        <IconButton
                            // Buttons cannot be nested in buttons, so we use a div
                            // here instead.
                            component="div"
                            // Inherit the color of the parent button instead of
                            // using the IconButton defaults.
                            color="inherit"
                            onClick={handleClose}
                            sx={{ bgcolor: "fill.faint" }}
                        >
                            <CloseIcon />
                        </IconButton>
                    )}
                </Stack>
            </RippleDisabledButton>
        </Snackbar>
    );
};
