import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import { errorDialogAttributes } from "ente-base/components/utils/dialog";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import log from "ente-base/log";
import { saveStringAsFile } from "ente-base/utils/web";
import { t } from "i18next";
import { useCallback, useEffect, useState, type ComponentType } from "react";

export interface RecoveryKeyPresentationProps {
    recoveryKey: string | undefined;
    onClose: () => void;
    onSave: () => void;
}

interface RecoveryKeyContentsProps extends ModalVisibilityProps {
    getRecoveryKeyMnemonic: () => Promise<string>;
    showMiniDialog: (attributes: MiniDialogAttributes) => void;
    presentation: ComponentType<RecoveryKeyPresentationProps>;
}

export function RecoveryKeyContents({
    open,
    onClose,
    getRecoveryKeyMnemonic,
    showMiniDialog,
    presentation: Presentation,
}: RecoveryKeyContentsProps): React.JSX.Element {
    const [recoveryKey, setRecoveryKey] = useState<string | undefined>();

    const handleLoadError = useCallback(
        (e: unknown) => {
            log.error("Failed to generate recovery key", e);
            showMiniDialog(
                errorDialogAttributes(t("recovery_key_generation_failed")),
            );
            onClose();
        },
        [onClose, showMiniDialog],
    );

    useEffect(() => {
        if (!open) return;

        void getRecoveryKeyMnemonic()
            .then((key) => setRecoveryKey(key))
            .catch(handleLoadError);
    }, [open, getRecoveryKeyMnemonic, handleLoadError]);

    function handleSaveClick() {
        if (!recoveryKey) return;
        saveRecoveryKeyMnemonicAsFile(recoveryKey);
        onClose();
    }

    return (
        <Presentation
            recoveryKey={recoveryKey}
            onClose={onClose}
            onSave={handleSaveClick}
        />
    );
}

const saveRecoveryKeyMnemonicAsFile = (key: string) =>
    saveStringAsFile(key, "ente-recovery-key.txt");
