import { Input, Stack, TextField, Typography } from "@mui/material";
import { AccountsPageFooter } from "ente-accounts/components/layouts/centered-paper";
import {
    replaceSavedLocalUser,
    saveSRPAttributes,
} from "ente-accounts/services/accounts-db";
import { getSRPAttributes } from "ente-accounts/services/srp";
import { sendOTT } from "ente-accounts/services/user";
import { appName } from "ente-base/app";
import { LinkButton } from "ente-base/components/LinkButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { HTTPError } from "ente-base/http";
import { JOIN_ALBUM_CONTEXT_KEY } from "ente-base/join-album";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useState } from "react";
import { z } from "zod";
import { AccountsPageTitleWithCaption } from "./LoginComponents";

interface LoginContentsProps {
    host: string | undefined;
    onSignUp: () => void;
    presentation?: React.ComponentType<LoginPresentationProps>;
}

export interface LoginPresentationProps {
    email: string;
    emailError: string | undefined;
    host: string | undefined;
    isSubmitting: boolean;
    isJoinAlbumContext: boolean;
    isEnsu: boolean;
    onEmailChange: React.ChangeEventHandler<
        HTMLInputElement | HTMLTextAreaElement
    >;
    onSubmit: React.SubmitEventHandler<HTMLFormElement>;
    onSignUp: () => void;
    onCancel: () => void;
}

export const LoginContents: React.FC<LoginContentsProps> = ({
    onSignUp,
    host,
    presentation: Presentation,
}) => {
    const router = useRouter();
    const [isJoinAlbumContext, setIsJoinAlbumContext] = useState(false);
    const isEnsu = appName === "ensu";

    useEffect(() => {
        const joinAlbumContext = sessionStorage.getItem(JOIN_ALBUM_CONTEXT_KEY);
        setIsJoinAlbumContext(!!joinAlbumContext);
    }, []);

    const loginUser = useCallback(
        async (email: string, setFieldError: (message: string) => void) => {
            const srpAttributes = await getSRPAttributes(email);
            if (!srpAttributes || srpAttributes.isEmailMFAEnabled) {
                try {
                    await sendOTT(email, "login");
                } catch (e) {
                    if (e instanceof HTTPError && e.res.status === 404) {
                        let errorCode: string | undefined;
                        try {
                            errorCode = z
                                .object({ code: z.string() })
                                .parse(await e.res.json()).code;
                        } catch (parseErr) {
                            log.warn(
                                "Ignoring error when parsing error payload",
                                parseErr,
                            );
                        }
                        if (errorCode === "USER_NOT_REGISTERED") {
                            setFieldError(t("email_not_registered"));
                            return;
                        }
                        if (errorCode === "USER_SIGNUP_INCOMPLETE") {
                            setFieldError(
                                t("account_setup_incomplete_create_account"),
                            );
                            return;
                        }
                    }
                    throw e;
                }
                replaceSavedLocalUser({ email });
                void router.push("/verify");
            } else {
                replaceSavedLocalUser({ email });
                saveSRPAttributes(srpAttributes);
                void router.push("/credentials");
            }
        },
        [router],
    );

    const formik = useFormik({
        initialValues: { email: "" },
        onSubmit: async ({ email }, { setFieldError }) => {
            const setEmailFieldError = (message: string) =>
                setFieldError("email", message);

            if (!email) {
                setEmailFieldError(t("required"));
                return;
            }

            if (!z.email().safeParse(email).success) {
                setEmailFieldError(t("invalid_email_error"));
                return;
            }

            try {
                await loginUser(email, setEmailFieldError);
            } catch (e) {
                log.error("Failed to login", e);
                setEmailFieldError(t("generic_error"));
            }
        },
    });

    function handleCancel() {
        void router.push("/chat");
    }

    if (Presentation) {
        return (
            <Presentation
                email={formik.values.email}
                emailError={formik.errors.email}
                host={host}
                isSubmitting={formik.isSubmitting}
                isJoinAlbumContext={isJoinAlbumContext}
                isEnsu={isEnsu}
                onEmailChange={formik.handleChange}
                onSubmit={formik.handleSubmit}
                onSignUp={onSignUp}
                onCancel={handleCancel}
            />
        );
    }

    return (
        <>
            <AccountsPageTitleWithCaption>
                {isJoinAlbumContext ? t("login_to_join_album") : t("login")}
            </AccountsPageTitleWithCaption>
            <form onSubmit={formik.handleSubmit}>
                <TextField
                    name="email"
                    value={formik.values.email}
                    onChange={formik.handleChange}
                    type="email"
                    autoComplete="username"
                    label={t("enter_email")}
                    fullWidth
                    autoFocus
                    margin="normal"
                    disabled={formik.isSubmitting}
                    error={!!formik.errors.email}
                    helperText={formik.errors.email ?? " "}
                />
                <Input sx={{ display: "none" }} type="password" value="" />
                <LoadingButton
                    fullWidth
                    type="submit"
                    loading={formik.isSubmitting}
                    color="accent"
                >
                    {t("login")}
                </LoadingButton>
            </form>
            <AccountsPageFooter>
                <Stack sx={{ gap: 3, textAlign: "center" }}>
                    {isEnsu ? (
                        <LinkButton onClick={handleCancel}>
                            {t("cancel")}
                        </LinkButton>
                    ) : (
                        <LinkButton onClick={onSignUp}>
                            {t("no_account")}
                        </LinkButton>
                    )}
                    <Typography
                        variant="mini"
                        sx={{ color: "text.faint", minHeight: "16px" }}
                    >
                        {host ?? ""}
                    </Typography>
                </Stack>
            </AccountsPageFooter>
        </>
    );
};
