import { LockerAuthShell } from "@/components/auth/LockerAuthShell";
import type { AuthPageConfig } from "ente-accounts/components/auth/AuthPageProvider";
import { decryptBox } from "ente-locker-wasm";

export const authPageConfig: AuthPageConfig = {
    decryptBox,
    recoveryKeyMnemonic: async () => {
        const { recoveryKeyMnemonic } = await import("./services/recovery-key");
        return recoveryKeyMnemonic();
    },
    Shell: LockerAuthShell,
    keepLoginLoadingOnRedirect: true,
};
