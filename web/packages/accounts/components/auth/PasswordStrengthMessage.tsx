import type { PasswordStrength } from "ente-accounts/utils/password";
import { t } from "i18next";
import type React from "react";
import { Message, type MessageKind } from "./Message";

interface PasswordStrengthMessageProps {
    strength?: PasswordStrength;
    visible: boolean;
}

export function PasswordStrengthMessage({
    strength,
    visible,
}: PasswordStrengthMessageProps): React.JSX.Element {
    const displayedStrength = strength ?? "weak";

    const kind: MessageKind =
        displayedStrength === "weak"
            ? "error"
            : displayedStrength === "moderate"
              ? "warning"
              : "success";

    return (
        <Message kind={kind} visible={visible}>
            {t("password_strength", { context: displayedStrength })}
        </Message>
    );
}
