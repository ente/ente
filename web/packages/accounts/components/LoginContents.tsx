import { LoginForm } from "ente-accounts/components/auth/LoginForm";
import {
    replaceSavedLocalUser,
    saveSRPAttributes,
} from "ente-accounts/services/accounts-db";
import { getSRPAttributes } from "ente-accounts/services/srp";
import { sendOTT } from "ente-accounts/services/user";
import { appName } from "ente-base/app";
import { isNamedError } from "ente-base/error";
import { JOIN_ALBUM_CONTEXT_KEY } from "ente-base/join-album";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useState } from "react";
import { z } from "zod";

interface LoginContentsProps {
    host: string | undefined;
    onSignUp: () => void;
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
}) => {
    const router = useRouter();
    const [isJoinAlbumContext, setIsJoinAlbumContext] = useState(false);
    const isEnsu = appName === "ensu";

    useEffect(() => {
        const joinAlbumContext = sessionStorage.getItem(JOIN_ALBUM_CONTEXT_KEY);
        setIsJoinAlbumContext(!!joinAlbumContext);
    }, []);

    const loginUser = useCallback(
        async (email: string) => {
            const srpAttributes = await getSRPAttributes(email);
            if (!srpAttributes || srpAttributes.isEmailMFAEnabled) {
                await sendOTT(email, "login");
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
                await loginUser(email);
            } catch (e) {
                if (isNamedError(e, "not_registered")) {
                    setEmailFieldError(t("email_not_registered"));
                } else if (isNamedError(e, "signup_incomplete")) {
                    setEmailFieldError(
                        t("account_setup_incomplete_create_account"),
                    );
                } else {
                    log.error("Failed to login", e);
                    setEmailFieldError(t("generic_error"));
                }
            }
        },
    });

    function handleCancel() {
        void router.push("/chat");
    }

    return (
        <LoginForm
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
};
