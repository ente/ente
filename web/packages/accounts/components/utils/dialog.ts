import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import { t } from "i18next";

export const sessionExpiredDialogAttributes = (
    onLogin: () => void,
): MiniDialogAttributes => ({
    title: t("session_expired"),
    message: t("session_expired_message"),
    nonClosable: true,
    nonReplaceable: true,
    continue: { text: t("login"), action: onLogin },
    cancel: false,
});
