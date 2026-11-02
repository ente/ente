import { isDesktop } from "ente-base/app";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { reauthenticateWithAppLock } from "ente-new/photos/services/app-lock";
import { useCallback, useRef } from "react";

export const useGalleryAuthentication = () => {
    const {
        show: showAuthenticateUser,
        props: authenticateUserVisibilityProps,
    } = useModalVisibility();

    const onAuthenticateCallback = useRef<
        ((didAuthenticate: boolean) => void) | undefined
    >(undefined);

    const authenticateUserWithPasswordModal = useCallback(
        () =>
            new Promise<boolean>((resolve) => {
                onAuthenticateCallback.current = resolve;
                showAuthenticateUser();
            }),
        [],
    );

    const authenticateUser = useCallback(async () => {
        if (!isDesktop) return authenticateUserWithPasswordModal();

        const reauthResult = await reauthenticateWithAppLock();
        if (reauthResult === "authenticated") return true;
        if (reauthResult === "cancelled") return false;

        return authenticateUserWithPasswordModal();
    }, [authenticateUserWithPasswordModal]);

    const handleCloseAuthenticateUser = useCallback(() => {
        authenticateUserVisibilityProps.onClose();
        if (onAuthenticateCallback.current) {
            onAuthenticateCallback.current(false);
            onAuthenticateCallback.current = undefined;
        }
    }, [authenticateUserVisibilityProps.onClose]);

    const handleAuthenticate = useCallback(() => {
        if (onAuthenticateCallback.current) {
            onAuthenticateCallback.current(true);
            onAuthenticateCallback.current = undefined;
        }
    }, []);

    return {
        authenticateUser,
        authenticateUserDialogProps: {
            open: authenticateUserVisibilityProps.open,
            onClose: handleCloseAuthenticateUser,
            onAuthenticate: handleAuthenticate,
        },
    };
};
