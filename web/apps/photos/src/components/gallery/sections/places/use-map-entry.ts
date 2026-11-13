import { useBaseContext } from "ente-base/context";
import { useSettingsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import { updateMapEnabled } from "ente-new/photos/services/settings";
import { useCallback } from "react";

export const useMapEntry = (onOpen: () => void) => {
    const { mapEnabled } = useSettingsSnapshot();
    const { onGenericError } = useBaseContext();
    return useCallback(() => {
        void (async () => {
            if (!mapEnabled) {
                try {
                    await updateMapEnabled(true);
                } catch (error) {
                    onGenericError(error);
                    return;
                }
            }
            onOpen();
        })();
    }, [mapEnabled, onGenericError, onOpen]);
};
