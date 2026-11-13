import { shouldShowWhatsNew } from "@/services/changelog";
import { useModalVisibility } from "ente-base/components/utils/modal";
import log from "ente-base/log";
import { useEffect } from "react";
import { WhatsNew } from "./WhatsNew";

export const DesktopWhatsNew: React.FC = () => {
    const { show, props } = useModalVisibility();

    useEffect(() => {
        const electron = globalThis.electron;
        if (!electron) return;

        let cancelled = false;

        const check = async () => {
            if ((await shouldShowWhatsNew(electron)) && !cancelled) show();
        };

        void check().catch((error: unknown) => {
            log.warn("Failed to check whether to show What's New", error);
        });

        return () => {
            cancelled = true;
        };
    }, [show]);

    return <WhatsNew {...props} />;
};
