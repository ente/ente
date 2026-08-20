import { VerifyEmailForm } from "@/components/auth/VerifyEmailForm";
import { PhotosAuthShell } from "@/components/PhotosAuthShell";
import { featureFlags } from "@/featureFlags";
import AccountsVerifyPage, {
    type VerifyEmailPresentationProps,
} from "ente-accounts/pages/verify";
import type React from "react";

function VerifyEmailPresentation(
    props: VerifyEmailPresentationProps,
): React.JSX.Element {
    return (
        <PhotosAuthShell>
            <VerifyEmailForm {...props} />
        </PhotosAuthShell>
    );
}

function VerifyPage(): React.JSX.Element {
    if (!featureFlags.enableNewPhotosSignupFlow) {
        return <AccountsVerifyPage />;
    }

    return <AccountsVerifyPage presentation={VerifyEmailPresentation} />;
}

export default VerifyPage;
