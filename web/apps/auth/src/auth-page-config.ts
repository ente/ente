import { AuthShell } from "@/components/AuthShell";
import type { AuthPageConfig } from "ente-accounts/components/auth/AuthPageProvider";
import { decryptBox } from "ente-auth-wasm";
import { LoginFrame } from "./components/auth/LoginFrame";

export const authPageConfig: AuthPageConfig = {
    decryptBox,
    recoveryKeyMnemonic: async () => {
        const { recoveryKeyMnemonic } = await import("./services/recovery-key");
        return recoveryKeyMnemonic();
    },
    Shell: AuthShell,
    LoginFrame,
};
