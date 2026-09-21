import { PasskeyVerificationPresentation } from "@/components/auth/PasskeyVerificationForm";
import { PhotosAuthShell } from "@/components/PhotosAuthShell";
import type { AuthPageConfig } from "ente-accounts/components/auth/AuthPageProvider";
import { decryptBox } from "ente-photos-wasm";

export const authPageConfig: AuthPageConfig = {
    decryptBox,
    encryptWithRecoveryKey: async (data) => {
        const { encryptWithRecoveryKey } =
            await import("./services/recovery-key");
        return encryptWithRecoveryKey(data);
    },
    Shell: PhotosAuthShell,
    recoveryKeyCloseDestination: "/plan",
    passkeyPresentation: PasskeyVerificationPresentation,
};
