import { LockerAuthShell } from "@/components/auth/LockerAuthShell";
import type { AuthPageConfig } from "ente-accounts/components/auth/AuthPageProvider";
import { decryptBox } from "ente-locker-wasm";

export const authPageConfig: AuthPageConfig = {
    decryptBox,
    encryptWithRecoveryKey: async (data) => {
        const { encryptWithRecoveryKey } =
            await import("./services/recovery-key");
        return encryptWithRecoveryKey(data);
    },
    Shell: LockerAuthShell,
    keepLoginLoadingOnRedirect: true,
};
