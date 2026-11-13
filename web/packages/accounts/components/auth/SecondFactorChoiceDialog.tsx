import { styled } from "@mui/material";
import type { SecondFactorChoicePresentationProps } from "ente-accounts/components/SecondFactorChoice";
import { t } from "i18next";
import type React from "react";
import {
    AuthDialog,
    AuthDialogHeader,
    AuthDialogText,
    AuthDialogTitle,
} from "./AuthDialog";
import { Button } from "./Button";
import { authDialogContentLayout } from "./styles";

export function SecondFactorChoiceDialog({
    open,
    onDialogClose,
    onSelect,
}: SecondFactorChoicePresentationProps): React.JSX.Element {
    return (
        <AuthDialog
            open={open}
            onClose={onDialogClose}
            ariaLabelledby="second-factor-choice-title"
        >
            <ContentRoot>
                <AuthDialogHeader>
                    <AuthDialogTitle id="second-factor-choice-title">
                        {t("two_factor")}
                    </AuthDialogTitle>
                    <AuthDialogText>
                        {t("auth_second_factor_choice_subtitle")}
                    </AuthDialogText>
                </AuthDialogHeader>
                <ButtonStack>
                    <Button
                        variant="primary"
                        fullWidth
                        onClick={() => onSelect("totp")}
                    >
                        {t("totp_login")}
                    </Button>
                    <Button
                        variant="secondary"
                        fullWidth
                        onClick={() => onSelect("passkey")}
                    >
                        {t("passkey_login")}
                    </Button>
                </ButtonStack>
            </ContentRoot>
        </AuthDialog>
    );
}

const ContentRoot = styled("div")(authDialogContentLayout);

const ButtonStack = styled("div")({
    display: "flex",
    flexDirection: "column",
    gap: "12px",
});
