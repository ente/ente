import { PeopleConsentDialog } from "@/components/gallery";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useMLStatusSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import { isMLEnabled } from "ente-new/photos/services/ml";
import {
    useCallback,
    useEffect,
    useRef,
    type ComponentProps,
    type ReactElement,
} from "react";

export const usePeopleEntry = ({
    isCurrentDestination,
    onUnavailable,
    onNavigate,
}: {
    isCurrentDestination: boolean;
    onUnavailable: () => void;
    onNavigate: () => void;
}) => {
    const mlStatus = useMLStatusSnapshot();
    const { show: showConsent, props: consentProps } = useModalVisibility();
    const pendingSearchReset = useRef<(() => void) | undefined>(undefined);
    useEffect(() => {
        if (isCurrentDestination && mlStatus?.phase == "disabled")
            onUnavailable();
    }, [isCurrentDestination, mlStatus?.phase, onUnavailable]);
    const showPeople = useCallback(
        (resetSearch?: () => void) => {
            if (!isMLEnabled()) {
                pendingSearchReset.current = resetSearch;
                showConsent();
                return false;
            }
            resetSearch?.();
            onNavigate();
            return true;
        },
        [showConsent, onNavigate],
    );
    const dialog: ReactElement<ComponentProps<typeof PeopleConsentDialog>> = (
        <PeopleConsentDialog
            {...consentProps}
            onClose={() => {
                pendingSearchReset.current = undefined;
                consentProps.onClose();
            }}
            onEnabled={() => {
                showPeople(pendingSearchReset.current);
            }}
        />
    );
    return { showPeople, dialog };
};
