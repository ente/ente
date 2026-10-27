import { Typography } from "@mui/material";
import { AccountsPageContents } from "ente-accounts/components/layouts/centered-paper";
import {
    singleInputPagePaperSx,
    v2TitleSx,
} from "ente-base/components/SingleInput.styles";
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
        <AccountsPageContents paperSx={singleInputPagePaperSx}>
            <Typography sx={v2TitleSx}>{t("password")}</Typography>
            <SingleInputForm
                autoFocus={false}
                inputType="password"
                label={t("password")}
                submitButtonTitle={t("unlock")}
                onSubmit={handleSubmit}
            />
        </AccountsPageContents>
    );
};
