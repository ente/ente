import { Input, Stack, TextField } from "@mui/material";
import { isWeakPassword } from "ente-accounts/utils/password";
import { ShowHidePasswordInputAdornment } from "ente-base/components/mui/PasswordInputAdornment";
import React, { useState } from "react";
import type { LegacyRecoverySession } from "..";
import { ActionButton } from "./ActionButton";
import { LegacyPageFrame } from "./LegacyPageFrame";

interface LegacyResetPasswordPageProps {
    session: LegacyRecoverySession;
    isSubmitting: boolean;
    onBack: () => void;
    onSubmit: (password: string) => Promise<void>;
}

export const LegacyResetPasswordPage: React.FC<
    LegacyResetPasswordPageProps
> = ({ session, isSubmitting, onBack, onSubmit }) => {
    const email = session.user.email;
    const [password, setPassword] = useState("");
    const [confirmPassword, setConfirmPassword] = useState("");
    const [showPassword, setShowPassword] = useState(false);
    const [showConfirmPassword, setShowConfirmPassword] = useState(false);
    const [errorMessage, setErrorMessage] = useState<string | undefined>();

    const passwordMismatch =
        !!confirmPassword && password !== confirmPassword
            ? "Passwords do not match."
            : undefined;
    const passwordTooWeak =
        !!password && isWeakPassword(password)
            ? "Use a stronger password."
            : undefined;

    const canSubmit =
        !!password &&
        !!confirmPassword &&
        !isWeakPassword(password) &&
        password === confirmPassword &&
        !isSubmitting;

    const handleSubmit = async () => {
        setErrorMessage(undefined);
        try {
            await onSubmit(password);
        } catch (error) {
            setErrorMessage(
                error instanceof Error
                    ? error.message
                    : "Something went wrong while resetting the password.",
            );
        }
    };

    return (
        <LegacyPageFrame
            title="Reset password"
            description={`Enter new password for ${email} account. You will be able to use this password to login into ${email} account.`}
            onBack={onBack}
        >
            <Stack sx={{ gap: 2, px: 0.5 }}>
                <Input
                    sx={{ display: "none" }}
                    name="email"
                    type="email"
                    autoComplete="username"
                    value={email}
                />
                <TextField
                    autoFocus
                    fullWidth
                    type={showPassword ? "text" : "password"}
                    label="Password"
                    autoComplete="new-password"
                    value={password}
                    onChange={(event) => {
                        setPassword(event.target.value);
                        setErrorMessage(undefined);
                    }}
                    error={!!passwordTooWeak}
                    helperText={passwordTooWeak ?? " "}
                    slotProps={{
                        input: {
                            endAdornment: (
                                <ShowHidePasswordInputAdornment
                                    showPassword={showPassword}
                                    onToggle={() =>
                                        setShowPassword((value) => !value)
                                    }
                                />
                            ),
                        },
                    }}
                />
                <TextField
                    fullWidth
                    type={showConfirmPassword ? "text" : "password"}
                    label="Confirm password"
                    autoComplete="new-password"
                    value={confirmPassword}
                    onChange={(event) => {
                        setConfirmPassword(event.target.value);
                        setErrorMessage(undefined);
                    }}
                    error={!!(passwordMismatch || errorMessage)}
                    helperText={passwordMismatch ?? errorMessage ?? " "}
                    slotProps={{
                        input: {
                            endAdornment: (
                                <ShowHidePasswordInputAdornment
                                    showPassword={showConfirmPassword}
                                    onToggle={() =>
                                        setShowConfirmPassword(
                                            (value) => !value,
                                        )
                                    }
                                />
                            ),
                        },
                    }}
                />
                <ActionButton
                    fullWidth
                    buttonType="primary"
                    loading={isSubmitting}
                    disabled={!canSubmit}
                    onClick={() => void handleSubmit()}
                    sx={{ mt: 2 }}
                >
                    Reset password
                </ActionButton>
            </Stack>
        </LegacyPageFrame>
    );
};
