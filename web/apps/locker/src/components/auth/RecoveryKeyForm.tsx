import ContentCopyIcon from "@mui/icons-material/ContentCopy";
import DoneIcon from "@mui/icons-material/Done";
import { CircularProgress, styled } from "@mui/material";
import type { RecoveryKeyPresentationProps } from "ente-accounts/components/RecoveryKey";
import { useClipboardCopy } from "ente-base/components/utils/hooks";
import { t } from "i18next";
import type React from "react";
import { Button } from "./Button";
import { FormFooter } from "./FormFooter";
import { Message } from "./Message";
import { ScreenHeader } from "./ScreenHeader";
import { authFocusRing } from "./styles";

export function RecoveryKeyForm({
    recoveryKey,
    onClose,
    onSave,
}: RecoveryKeyPresentationProps): React.JSX.Element {
    const [copied, handleCopy] = useClipboardCopy(recoveryKey ?? "");
    const CopyIcon = copied ? DoneIcon : ContentCopyIcon;

    return (
        <>
            <ScreenHeader
                title={t("auth_recovery_key_title")}
                subtitle={t("recovery_key_description")}
            />
            <RecoveryKeyBox>
                {recoveryKey ? (
                    <>
                        <RecoveryKeyText>{recoveryKey}</RecoveryKeyText>
                        <CopyButton
                            type="button"
                            onClick={handleCopy}
                            aria-label={
                                copied
                                    ? t("copied")
                                    : t("auth_copy_recovery_key")
                            }
                        >
                            <CopyIcon fontSize="small" />
                        </CopyButton>
                    </>
                ) : (
                    <CircularProgress
                        size={24}
                        sx={{ color: "var(--locker-auth-primary)" }}
                    />
                )}
            </RecoveryKeyBox>
            <Message note>{t("key_not_stored_note")}</Message>
            <FormFooter>
                <Actions>
                    <Button fullWidth variant="secondary" onClick={onClose}>
                        {t("do_this_later")}
                    </Button>
                    <Button fullWidth onClick={onSave} disabled={!recoveryKey}>
                        {t("save_key")}
                    </Button>
                </Actions>
            </FormFooter>
        </>
    );
}

const RecoveryKeyBox = styled("div")({
    minHeight: "128px",
    padding: "20px",
    borderRadius: "16px",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    position: "relative",
    boxSizing: "border-box",
    backgroundColor: "var(--locker-auth-field)",
    boxShadow: "inset 0 0 0 1px var(--locker-auth-stroke)",
});

const RecoveryKeyText = styled("p")({
    margin: 0,
    paddingRight: "28px",
    fontSize: "15px",
    fontWeight: 500,
    lineHeight: "24px",
    wordBreak: "break-word",
    color: "var(--locker-auth-text)",
});

const CopyButton = styled("button")({
    width: "32px",
    height: "32px",
    padding: 0,
    border: 0,
    borderRadius: "8px",
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    position: "absolute",
    top: "12px",
    right: "12px",
    backgroundColor: "transparent",
    color: "var(--locker-auth-text-muted)",
    cursor: "pointer",
    "&:focus-visible": authFocusRing,
});

const Actions = styled("div")({ display: "flex", gap: "12px" });
