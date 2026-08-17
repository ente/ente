// This hook is in a separate file from SecondFactorChoice.tsx so that fast
// refresh keeps working.

import type { EmailOrSRPVerificationResponse } from "ente-accounts/services/user";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useCallback, useMemo, useRef } from "react";
import type { SecondFactorType } from "../SecondFactorChoice";

export const useSecondFactorChoiceIfNeeded = () => {
    const resolveSecondFactorChoice = useRef<
        | ((value: SecondFactorType | PromiseLike<SecondFactorType>) => void)
        | undefined
    >(undefined);
    const {
        show: showSecondFactorChoice,
        props: secondFactorChoiceVisibilityProps,
    } = useModalVisibility();

    const onSelect = useCallback((factor: SecondFactorType) => {
        const resolve = resolveSecondFactorChoice.current!;
        resolveSecondFactorChoice.current = undefined;
        resolve(factor);
    }, []);

    const secondFactorChoiceProps = useMemo(
        () => ({ ...secondFactorChoiceVisibilityProps, onSelect }),
        [secondFactorChoiceVisibilityProps, onSelect],
    );

    const userVerificationResultAfterResolvingSecondFactorChoice = useCallback(
        async (response: EmailOrSRPVerificationResponse) => {
            const {
                twoFactorSessionID: _twoFactorSessionIDV1,
                twoFactorSessionIDV2: _twoFactorSessionIDV2,
                passkeySessionID: _passkeySessionID,
            } = response;

            // Use || and not ?? since an unset _twoFactorSessionIDV1 is an
            // empty string, not undefined.
            const _twoFactorSessionID =
                _twoFactorSessionIDV1 || _twoFactorSessionIDV2;

            let passkeySessionID: string | undefined;
            let twoFactorSessionID: string | undefined;
            if (_twoFactorSessionID && _passkeySessionID) {
                const choice = await new Promise<SecondFactorType>(
                    (resolve) => {
                        resolveSecondFactorChoice.current = resolve;
                        showSecondFactorChoice();
                    },
                );
                switch (choice) {
                    case "passkey":
                        passkeySessionID = _passkeySessionID;
                        break;
                    case "totp":
                        twoFactorSessionID = _twoFactorSessionID;
                        break;
                }
            } else {
                passkeySessionID = _passkeySessionID;
                twoFactorSessionID = _twoFactorSessionID;
            }

            return { ...response, passkeySessionID, twoFactorSessionID };
        },
        [showSecondFactorChoice],
    );

    return {
        secondFactorChoiceProps,
        userVerificationResultAfterResolvingSecondFactorChoice,
    };
};
