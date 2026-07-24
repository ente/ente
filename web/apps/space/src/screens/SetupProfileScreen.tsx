import { Box } from "@mui/material";
import { SpaceBackIcon } from "components/SpaceBackIcon";
import React, { useState } from "react";
import { spaceTouchTargetSize } from "styles/touchTargets";

export const setupProfileBackground = "#FAFAFA";

const green = "#08C225";
const textBase = "#000";
const textLight = "#969696";
const warning = "#F63A3A";
const setupProfileFormID = "space-setup-profile-form";

export interface SetupProfile {
    avatarUrl: string | null;
    avatarKeyVersion?: number;
    avatarObjectID?: string;
    avatarUpdatedAt?: string;
    coverUrl?: string | null;
    coverKeyVersion?: number;
    coverObjectID?: string;
    coverUpdatedAt?: string;
    fullName: string;
    username: string;
    spaceId?: string;
    spaceSlug?: string;
}

export interface SetupProfileInput extends SetupProfile {
    avatarFile?: File | null;
    coverFile?: File | null;
}

export type SetupProfileDetails = Pick<SetupProfile, "fullName" | "username">;

interface SetupProfileScreenProps {
    initialProfile?: SetupProfileDetails | null;
    onBack: () => void;
    onContinue: (profile: SetupProfileDetails) => void;
    onUsernameChange?: (username: string) => void;
    usernameStatus?: "available" | "unavailable";
}

interface TextInputProps {
    autoCapitalize?: React.HTMLAttributes<HTMLInputElement>["autoCapitalize"];
    endAdornment?: React.ReactNode;
    id: string;
    label: string;
    onChange?: (value: string) => void;
    placeholder?: string;
    required?: boolean;
    startAdornment?: React.ReactNode;
    value?: string;
}

const CheckIcon: React.FC = () => (
    <Box
        component="svg"
        viewBox="0 0 20 20"
        aria-hidden
        sx={{ display: "block", height: 18, width: 18 }}
    >
        <path
            d="M4.5 10.25L8.25 14L15.75 6"
            fill="none"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="2.2"
        />
    </Box>
);

const XIcon: React.FC = () => (
    <Box
        component="svg"
        viewBox="0 0 20 20"
        aria-hidden
        sx={{ display: "block", height: 18, width: 18 }}
    >
        <path
            d="M5.75 5.75L14.25 14.25M14.25 5.75L5.75 14.25"
            fill="none"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="2.2"
        />
    </Box>
);

const UsernameStatusIcon: React.FC<{
    status?: "available" | "unavailable";
}> = ({ status }) => {
    if (!status) return null;

    return (
        <Box
            component="span"
            role="img"
            aria-label={
                status == "available"
                    ? "Username available"
                    : "Username unavailable"
            }
            sx={{
                alignItems: "center",
                color: status == "available" ? green : warning,
                display: "flex",
                flexShrink: 0,
                justifyContent: "center",
                ml: 1,
            }}
        >
            {status == "available" ? <CheckIcon /> : <XIcon />}
        </Box>
    );
};

const TextInput: React.FC<TextInputProps> = ({
    autoCapitalize,
    endAdornment,
    id,
    label,
    onChange,
    placeholder,
    required,
    startAdornment,
    value,
}) => (
    <Box sx={{ width: "100%" }}>
        <Box
            component="label"
            htmlFor={id}
            sx={{
                color: textBase,
                display: "flex",
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 14,
                fontWeight: 500,
                gap: "2px",
                lineHeight: "20px",
                mb: "9px",
            }}
        >
            {label}
            {required && (
                <Box component="span" sx={{ color: warning }}>
                    *
                </Box>
            )}
        </Box>
        <Box
            sx={{
                alignItems: "center",
                bgcolor: "white",
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
            {startAdornment}
            <Box
                component="input"
                autoCapitalize={autoCapitalize}
                id={id}
                onChange={(event) => onChange?.(event.target.value)}
                placeholder={placeholder}
                type="text"
                value={value}
                sx={{
                    bgcolor: "transparent",
                    border: 0,
                    color: textBase,
                    flex: 1,
                    fontFamily: '"Inter Variable", Inter, sans-serif',
                    fontSize: 14,
                    fontWeight: 500,
                    lineHeight: "20px",
                    minWidth: 0,
                    outline: 0,
                    p: 0,
                    "&::placeholder": { color: textLight, opacity: 1 },
                }}
            />
            {endAdornment}
        </Box>
    </Box>
);

export const SetupProfileScreen: React.FC<SetupProfileScreenProps> = ({
    initialProfile,
    onBack,
    onContinue,
    onUsernameChange,
    usernameStatus,
}) => {
    const [username, setUsername] = useState(initialProfile?.username ?? "");
    const [fullName, setFullName] = useState(initialProfile?.fullName ?? "");
    const canContinue =
        usernameStatus != "unavailable" &&
        username.trim().length > 0 &&
        fullName.trim().length > 0;

    const handleUsernameChange = (value: string) => {
        setUsername(value);
        onUsernameChange?.(value);
    };

    const handleSubmit: React.SubmitEventHandler<HTMLFormElement> = (event) => {
        event.preventDefault();
        if (canContinue) {
            onContinue({
                fullName: fullName.trim(),
                username: username.trim(),
            });
        }
    };

    return (
        <Box
            component="main"
            sx={{
                bgcolor: setupProfileBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                overflow: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
            }}
        >
            <Box
                sx={{
                    bgcolor: setupProfileBackground,
                    boxSizing: "border-box",
                    display: "flex",
                    flexDirection: "column",
                    minHeight: "100svh",
                    mx: "auto",
                    pb: "120px",
                    px: 3,
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: 390 },
                }}
            >
                <Box
                    component="header"
                    sx={{
                        display: "grid",
                        gridTemplateColumns: `${spaceTouchTargetSize}px 1fr ${spaceTouchTargetSize}px`,
                        height: spaceTouchTargetSize,
                        mt: "32px",
                        width: "100%",
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label="Back"
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
                            p: 0,
                            width: spaceTouchTargetSize,
                            "&:focus-visible": {
                                borderRadius: "50%",
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <SpaceBackIcon />
                    </Box>
                    <Box
                        component="h1"
                        sx={{
                            alignSelf: "center",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 20,
                            fontWeight: 600,
                            justifySelf: "center",
                            lineHeight: "28px",
                            m: 0,
                            whiteSpace: "nowrap",
                        }}
                    >
                        Create your profile
                    </Box>
                    <Box />
                </Box>

                <Box
                    component="form"
                    id={setupProfileFormID}
                    noValidate
                    onSubmit={handleSubmit}
                    sx={{
                        display: "flex",
                        flexDirection: "column",
                        gap: "24px",
                        mt: "52px",
                        width: "100%",
                    }}
                >
                    <TextInput
                        autoCapitalize="none"
                        endAdornment={
                            <UsernameStatusIcon status={usernameStatus} />
                        }
                        id="space-setup-profile-username"
                        label="Username"
                        onChange={handleUsernameChange}
                        placeholder="username"
                        required
                        startAdornment={
                            <Box
                                component="span"
                                aria-hidden
                                sx={{
                                    color: textBase,
                                    flexShrink: 0,
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 14,
                                    fontWeight: 500,
                                    lineHeight: "20px",
                                }}
                            >
                                ente.space/
                            </Box>
                        }
                        value={username}
                    />
                    <TextInput
                        id="space-setup-profile-name"
                        label="Name"
                        onChange={setFullName}
                        placeholder="Enter your name"
                        required
                        value={fullName}
                    />
                </Box>

                <Box
                    sx={{
                        bgcolor: setupProfileBackground,
                        bottom: 0,
                        boxSizing: "border-box",
                        left: "50%",
                        maxWidth: 390,
                        p: 3,
                        position: "fixed",
                        transform: "translateX(-50%)",
                        width: "100%",
                    }}
                >
                    <Box
                        className={canContinue ? "green-bg" : undefined}
                        component="button"
                        form={setupProfileFormID}
                        type="submit"
                        disabled={!canContinue}
                        sx={{
                            alignItems: "center",
                            bgcolor: canContinue ? green : "#F5F5F5",
                            border: 0,
                            borderRadius: "20px",
                            color: canContinue ? "white" : textLight,
                            cursor: canContinue ? "pointer" : "default",
                            display: "flex",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 500,
                            height: 48,
                            justifyContent: "center",
                            lineHeight: "20px",
                            p: "14px 24px",
                            width: "100%",
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 3,
                            },
                            "&:hover": canContinue
                                ? { bgcolor: "#07AE22" }
                                : undefined,
                        }}
                    >
                        Next
                    </Box>
                </Box>
            </Box>
        </Box>
    );
};
