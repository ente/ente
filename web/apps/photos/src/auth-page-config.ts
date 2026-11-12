import { PasskeyVerificationPresentation } from "@/components/auth/PasskeyVerificationForm";
import { PhotosAuthShell } from "@/components/PhotosAuthShell";
import type { AuthPageConfig } from "ente-accounts/components/auth/AuthPageProvider";
import { decryptBox } from "ente-photos-wasm";

export const authPageConfig: AuthPageConfig = {
    decryptBox,
    recoveryKeyMnemonic: async () => {
        const { recoveryKeyMnemonic } = await import("./services/recovery-key");
        return recoveryKeyMnemonic();
    },
    Shell: PhotosAuthShell,
    recoveryKeyCloseDestination: "/plan",
    passkeyPresentation: PasskeyVerificationPresentation,
};
