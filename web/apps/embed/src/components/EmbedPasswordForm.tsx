import { Stack, Typography } from "@mui/material";
import {
    AccountsPageContents,
    AccountsPageTitle,
} from "ente-accounts/components/layouts/centered-paper";
import {
    SingleInputForm,
    type SingleInputFormProps,
} from "ente-base/components/SingleInputForm";
import { t } from "i18next";

interface EmbedPasswordFormProps {
    onSubmit: (password: string) => Promise<void>;
}

export const EmbedPasswordForm: React.FC<EmbedPasswordFormProps> = ({
    onSubmit,
}) => {
    const handleSubmit: SingleInputFormProps["onSubmit"] = async (
        password,
        setFieldError,
    ) => {
        try {
            await onSubmit(password);
        } catch (e) {
            if (e instanceof Error) {
                setFieldError(e.message);
            } else {
                setFieldError(t("generic_error"));
            }
        }
    };

    return (
        <AccountsPageContents>
            <AccountsPageTitle>{t("password")}</AccountsPageTitle>
            <Stack>
                <Typography variant="small" sx={{ color: "text.muted", mb: 2 }}>
                    {t("link_password_description")}
                </Typography>
                <SingleInputForm
                    autoFocus={false}
                    inputType="password"
                    label={t("password")}
                    submitButtonColor="primary"
                    submitButtonTitle={t("unlock")}
                    onSubmit={handleSubmit}
                />
            </Stack>
        </AccountsPageContents>
    );
};
