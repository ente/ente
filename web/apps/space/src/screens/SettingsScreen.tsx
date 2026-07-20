import {
    ArrowLeft02Icon,
    Camera01Icon,
    ArrowRight01Icon as ChevronRightIcon,
    CustomerSupportIcon,
    Image01Icon,
    Logout05Icon,
    UserEdit01Icon,
    UserIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon, type IconSvgElement } from "@hugeicons/react";
import { Box } from "@mui/material";
import { ConfirmationActionSheet } from "components/ConfirmationActionSheet";
import type { SpaceActionPhase } from "components/SpaceActionFeedback";
import { SpaceButtonSpinner } from "components/SpaceButtonSpinner";
import React from "react";
import { spaceTouchTargetSize } from "styles/touchTargets";

export const settingsBackground = "#FAFAFA";

const green = "#08C225";
const textBase = "#000";
const rowBackground = "#FFFFFF";
const dangerColor = "#F63A3A";
const iconMuted = "#8C8C8C";
const textLight = "#969696";
const supportMailURL = "mailto:support@ente.com";
const spaceLinks = [
    {
        label: "Discord",
        src: "/images/discord.svg",
        url: "https://ente.com/discord",
    },
    {
        label: "YouTube",
        src: "/images/youtube.svg",
        url: "https://www.youtube.com/@entestudio",
    },
    {
        label: "GitHub",
        src: "/images/github.svg",
        url: "https://github.com/ente-io/ente",
    },
    {
        label: "X",
        src: "/images/new-twitter.svg",
        url: "https://twitter.com/enteio",
    },
    {
        label: "Mastodon",
        src: "/images/mastodon.svg",
        url: "https://fosstodon.org/@ente",
    },
    {
        label: "Reddit",
        src: "/images/reddit.svg",
        url: "https://reddit.com/r/enteio",
    },
] as const;

interface SettingsScreenProps {
    onLogout: () => Promise<void>;
    onBack?: () => void;
    onOpenProfile: () => void;
}

interface SettingsRowProps {
    danger?: boolean;
    href?: string;
    icon: IconSvgElement;
    label: string;
    onClick?: () => void;
}

interface SpaceIconProps {
    label: string;
    src: string;
    url: string;
}

interface ProfileSettingsScreenProps {
    onBack: () => void;
    onChangeCoverImage: () => void;
    onChangeName: () => void;
    onChangeProfilePicture: () => void;
}

interface ChangeNameSettingsScreenProps {
    errorMessage?: string;
    initialName: string;
    isSaving?: boolean;
    onBack: () => void;
    onSave: (name: string) => void;
}

const SettingsRow: React.FC<SettingsRowProps> = ({
    danger,
    href,
    icon,
    label,
    onClick,
}) => (
    <Box
        component={href ? "a" : "button"}
        href={href}
        rel={href?.startsWith("http") ? "noopener noreferrer" : undefined}
        target={href?.startsWith("http") ? "_blank" : undefined}
        type={href ? undefined : "button"}
        onClick={onClick}
        sx={{
            alignItems: "center",
            bgcolor: rowBackground,
            border: 0,
            borderRadius: "20px",
            boxSizing: "border-box",
            cursor: "pointer",
            display: "flex",
            justifyContent: "space-between",
            minHeight: 56,
            p: "8px",
            textDecoration: "none",
            textAlign: "left",
            transition: "background-color 120ms ease",
            width: "100%",
            "&:active": { bgcolor: "rgba(0, 0, 0, 0.025)" },
            "&:focus-visible": {
                outline: `2px solid ${green}`,
                outlineOffset: 2,
            },
            "&:hover": { bgcolor: "rgba(0, 0, 0, 0.025)" },
        }}
    >
        <Box
            sx={{
                alignItems: "center",
                display: "flex",
                gap: "4px",
                minWidth: 0,
            }}
        >
            <Box
                sx={{
                    alignItems: "center",
                    borderRadius: "12px",
                    color: danger ? dangerColor : iconMuted,
                    display: "flex",
                    flexShrink: 0,
                    height: 40,
                    justifyContent: "center",
                    width: 40,
                }}
            >
                <HugeiconsIcon icon={icon} size={20} strokeWidth={1.6} />
            </Box>
            <Box
                sx={{
                    color: danger ? dangerColor : textBase,
                    fontFamily: '"Inter Variable", Inter, sans-serif',
                    fontSize: 14,
                    fontWeight: 600,
                    lineHeight: "17px",
                    minWidth: 0,
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                }}
            >
                {label}
            </Box>
        </Box>
        <HugeiconsIcon
            aria-hidden
            icon={ChevronRightIcon}
            size={20}
            strokeWidth={1.8}
            style={{ color: textBase, flexShrink: 0 }}
        />
    </Box>
);

const SpaceIcon: React.FC<SpaceIconProps> = ({ label, src, url }) => (
    <Box
        aria-label={label}
        component="a"
        href={url}
        rel="noopener noreferrer"
        target="_blank"
        sx={{
            alignItems: "center",
            bgcolor: "transparent",
            border: 0,
            borderRadius: "10px",
            cursor: "pointer",
            display: "flex",
            height: spaceTouchTargetSize,
            justifyContent: "center",
            p: 0,
            textDecoration: "none",
            transition: "background-color 120ms ease",
            width: spaceTouchTargetSize,
            "&:active": { bgcolor: "rgba(0, 0, 0, 0.025)" },
            "&:focus-visible": {
                outline: `2px solid ${green}`,
                outlineOffset: 2,
            },
            "&:hover": { bgcolor: "rgba(0, 0, 0, 0.025)" },
        }}
    >
        <Box
            component="img"
            aria-hidden
            alt=""
            src={src}
            sx={{ display: "block", maxHeight: 24, maxWidth: 24 }}
        />
    </Box>
);

export const SettingsScreen: React.FC<SettingsScreenProps> = ({
    onLogout,
    onBack,
    onOpenProfile,
}) => {
    const [logoutSheetOpen, setLogoutSheetOpen] = React.useState(false);
    const [logoutActionPhase, setLogoutActionPhase] =
        React.useState<SpaceActionPhase | null>(null);
    const [logoutErrorMessage, setLogoutErrorMessage] = React.useState<
        string | null
    >(null);
    const isLogoutRunning = logoutActionPhase != null;

    const handleConfirmLogout = () => {
        setLogoutErrorMessage(null);
        setLogoutActionPhase("busy");
        void onLogout().catch((error: unknown) => {
            console.error("Failed to log out Space sessions", error);
            setLogoutActionPhase(null);
            setLogoutErrorMessage("Couldn't log out. Please try again.");
        });
    };

    const cancelLogout = () => {
        setLogoutSheetOpen(false);
        setLogoutErrorMessage(null);
    };

    return (
        <Box
            component="main"
            sx={{
                bgcolor: settingsBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                overflowX: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
            }}
        >
            <Box
                sx={{
                    bgcolor: settingsBackground,
                    boxSizing: "border-box",
                    display: "flex",
                    flexDirection: "column",
                    minHeight: "100svh",
                    mx: "auto",
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: 390 },
                }}
            >
                <Box
                    component="header"
                    sx={{
                        alignItems: "center",
                        display: "grid",
                        gridTemplateColumns: `${spaceTouchTargetSize}px 1fr ${spaceTouchTargetSize}px`,
                        height: 56,
                        px: 2,
                        width: "100%",
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label="Back to profile"
                        onClick={onBack}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            color: textBase,
                            cursor: onBack ? "pointer" : "default",
                            display: "flex",
                            height: spaceTouchTargetSize,
                            justifyContent: "flex-start",
                            ml: "-2px",
                            p: 0,
                            width: spaceTouchTargetSize,
                            "&:focus-visible": {
                                borderRadius: "50%",
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <HugeiconsIcon
                            icon={ArrowLeft02Icon}
                            size={24}
                            strokeWidth={1.8}
                        />
                    </Box>
                    <Box
                        component="h1"
                        sx={{
                            color: textBase,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 18,
                            fontWeight: 700,
                            justifySelf: "center",
                            lineHeight: "24px",
                            m: 0,
                        }}
                    >
                        Settings
                    </Box>
                </Box>

                <Box
                    component="section"
                    sx={{
                        display: "flex",
                        flexDirection: "column",
                        gap: "8px",
                        mt: "24px",
                        px: "14px",
                        width: "100%",
                    }}
                >
                    <SettingsRow
                        icon={UserIcon}
                        label="Profile"
                        onClick={onOpenProfile}
                    />
                    <SettingsRow
                        href={supportMailURL}
                        icon={CustomerSupportIcon}
                        label="Support"
                    />
                    <SettingsRow
                        danger
                        icon={Logout05Icon}
                        label="Logout"
                        onClick={() => setLogoutSheetOpen(true)}
                    />
                </Box>

                <Box sx={{ flex: 1, minHeight: 72 }} />

                <Box
                    sx={{
                        alignItems: "center",
                        display: "flex",
                        gap: "8px",
                        justifyContent: "center",
                        pb: "18px",
                    }}
                >
                    {spaceLinks.map((link) => (
                        <SpaceIcon
                            key={link.label}
                            label={link.label}
                            src={link.src}
                            url={link.url}
                        />
                    ))}
                </Box>
            </Box>
            <ConfirmationActionSheet
                open={logoutSheetOpen}
                title="Log out of Space?"
                description={
                    <>
                        This will also log you out of Space on
                        <br />
                        any other devices.
                    </>
                }
                confirmLabel="Yes, logout"
                confirmActionPhase={logoutActionPhase}
                confirmDisabled={isLogoutRunning}
                errorMessage={logoutErrorMessage}
                cancelDisabled={isLogoutRunning}
                onCancel={cancelLogout}
                onConfirm={handleConfirmLogout}
            />
        </Box>
    );
};

export const ProfileSettingsScreen: React.FC<ProfileSettingsScreenProps> = ({
    onBack,
    onChangeCoverImage,
    onChangeName,
    onChangeProfilePicture,
}) => (
    <Box
        component="main"
        sx={{
            bgcolor: settingsBackground,
            color: textBase,
            display: "grid",
            minHeight: "100svh",
            overflowX: "hidden",
            placeItems: { xs: "stretch", sm: "start center" },
        }}
    >
        <Box
            sx={{
                bgcolor: settingsBackground,
                boxSizing: "border-box",
                display: "flex",
                flexDirection: "column",
                minHeight: "100svh",
                mx: "auto",
                width: "100%",
                "@media (min-width: 600px)": { maxWidth: 390 },
            }}
        >
            <Box
                component="header"
                sx={{
                    alignItems: "center",
                    display: "grid",
                    gridTemplateColumns: `${spaceTouchTargetSize}px 1fr ${spaceTouchTargetSize}px`,
                    height: 56,
                    px: 2,
                    width: "100%",
                }}
            >
                <Box
                    component="button"
                    type="button"
                    aria-label="Back to settings"
                    onClick={onBack}
                    sx={{
                        alignItems: "center",
                        bgcolor: "transparent",
                        border: 0,
                        color: textBase,
                        cursor: "pointer",
                        display: "flex",
                        height: spaceTouchTargetSize,
                        justifyContent: "flex-start",
                        ml: "-2px",
                        p: 0,
                        width: spaceTouchTargetSize,
                        "&:focus-visible": {
                            borderRadius: "50%",
                            outline: `2px solid ${green}`,
                            outlineOffset: 2,
                        },
                    }}
                >
                    <HugeiconsIcon
                        icon={ArrowLeft02Icon}
                        size={24}
                        strokeWidth={1.8}
                    />
                </Box>
                <Box
                    component="h1"
                    sx={{
                        color: textBase,
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 18,
                        fontWeight: 700,
                        justifySelf: "center",
                        lineHeight: "24px",
                        m: 0,
                    }}
                >
                    Profile
                </Box>
            </Box>

            <Box
                component="section"
                sx={{
                    display: "flex",
                    flexDirection: "column",
                    gap: "8px",
                    mt: "24px",
                    px: "14px",
                    width: "100%",
                }}
            >
                <SettingsRow
                    icon={UserEdit01Icon}
                    label="Change name"
                    onClick={onChangeName}
                />
                <SettingsRow
                    icon={Camera01Icon}
                    label="Change profile picture"
                    onClick={onChangeProfilePicture}
                />
                <SettingsRow
                    icon={Image01Icon}
                    label="Change cover image"
                    onClick={onChangeCoverImage}
                />
            </Box>
        </Box>
    </Box>
);

export const ChangeNameSettingsScreen: React.FC<
    ChangeNameSettingsScreenProps
> = ({ errorMessage, initialName, isSaving = false, onBack, onSave }) => {
    const [name, setName] = React.useState(initialName);
    const trimmedName = name.trim();
    const canSave =
        !isSaving &&
        trimmedName.length > 0 &&
        trimmedName != initialName.trim();

    const handleSubmit: React.SubmitEventHandler<HTMLFormElement> = (event) => {
        event.preventDefault();
        if (canSave) onSave(trimmedName);
    };

    return (
        <Box
            component="main"
            sx={{
                bgcolor: settingsBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                overflowX: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
            }}
        >
            <Box
                sx={{
                    bgcolor: settingsBackground,
                    boxSizing: "border-box",
                    display: "flex",
                    flexDirection: "column",
                    minHeight: "100svh",
                    mx: "auto",
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: 390 },
                }}
            >
                <Box
                    component="header"
                    sx={{
                        alignItems: "center",
                        display: "grid",
                        gridTemplateColumns: `${spaceTouchTargetSize}px 1fr ${spaceTouchTargetSize}px`,
                        height: 56,
                        px: 2,
                        width: "100%",
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label="Back to profile settings"
                        onClick={onBack}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            color: textBase,
                            cursor: "pointer",
                            display: "flex",
                            height: spaceTouchTargetSize,
                            justifyContent: "flex-start",
                            ml: "-2px",
                            p: 0,
                            width: spaceTouchTargetSize,
                            "&:focus-visible": {
                                borderRadius: "50%",
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <HugeiconsIcon
                            icon={ArrowLeft02Icon}
                            size={24}
                            strokeWidth={1.8}
                        />
                    </Box>
                    <Box
                        component="h1"
                        sx={{
                            color: textBase,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 18,
                            fontWeight: 700,
                            justifySelf: "center",
                            lineHeight: "24px",
                            m: 0,
                        }}
                    >
                        Change name
                    </Box>
                </Box>

                <Box
                    component="form"
                    onSubmit={handleSubmit}
                    sx={{
                        boxSizing: "border-box",
                        display: "flex",
                        flex: 1,
                        flexDirection: "column",
                        width: "100%",
                    }}
                >
                    <Box sx={{ px: "14px", pt: "24px", width: "100%" }}>
                        <Box
                            component="label"
                            htmlFor="space-profile-name"
                            sx={{
                                color: textBase,
                                display: "block",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 500,
                                lineHeight: "20px",
                                mb: "9px",
                            }}
                        >
                            Name
                        </Box>
                        <Box
                            sx={{
                                alignItems: "center",
                                bgcolor: rowBackground,
                                borderRadius: "16px",
                                display: "flex",
                                height: 52,
                                px: 2,
                                width: "100%",
                                "&:focus-within": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 1,
                                },
                            }}
                        >
                            <Box
                                id="space-profile-name"
                                component="input"
                                autoComplete="name"
                                onChange={(event) =>
                                    setName(event.target.value)
                                }
                                placeholder="Enter your name"
                                type="text"
                                value={name}
                                sx={{
                                    bgcolor: "transparent",
                                    border: 0,
                                    color: textBase,
                                    flex: 1,
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 14,
                                    fontWeight: 500,
                                    lineHeight: "20px",
                                    minWidth: 0,
                                    outline: 0,
                                    p: 0,
                                    "&::placeholder": {
                                        color: textLight,
                                        opacity: 1,
                                    },
                                }}
                            />
                        </Box>
                    </Box>

                    {errorMessage && (
                        <Box
                            role="alert"
                            sx={{
                                color: dangerColor,
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 13,
                                fontWeight: 500,
                                lineHeight: "18px",
                                mt: 2,
                                px: "14px",
                            }}
                        >
                            {errorMessage}
                        </Box>
                    )}

                    <Box sx={{ flex: 1, minHeight: 72 }} />

                    <Box
                        sx={{
                            boxSizing: "border-box",
                            mb: "calc(24px + env(safe-area-inset-bottom))",
                            px: 3,
                            width: "100%",
                        }}
                    >
                        <Box
                            className="green-bg"
                            component="button"
                            type="submit"
                            aria-label={isSaving ? "Saving name" : undefined}
                            aria-busy={isSaving ? true : undefined}
                            disabled={!canSave}
                            sx={{
                                alignItems: "center",
                                bgcolor: green,
                                border: 0,
                                borderRadius: "20px",
                                color: "white",
                                cursor: canSave ? "pointer" : "default",
                                display: "flex",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 500,
                                height: 44,
                                justifyContent: "center",
                                lineHeight: "20px",
                                opacity: canSave || isSaving ? 1 : 0.45,
                                px: 2,
                                width: "100%",
                                "&:focus-visible": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 3,
                                },
                                "&:hover": {
                                    bgcolor: canSave ? "#07AE22" : green,
                                },
                            }}
                        >
                            {isSaving ? <SpaceButtonSpinner /> : "Save"}
                        </Box>
                    </Box>
                </Box>
            </Box>
        </Box>
    );
};
