import { PhotosAuthShell } from "@/components/PhotosAuthShell";
import { TwoFactorForm } from "ente-accounts/components/auth/TwoFactorForm";
import AccountsTwoFactorVerifyPage, {
    type TwoFactorVerifyPresentationProps,
} from "ente-accounts/pages/two-factor/verify";
import type React from "react";

function TwoFactorPresentation(
    props: TwoFactorVerifyPresentationProps,
): React.JSX.Element {
    return (
        <PhotosAuthShell>
            <TwoFactorForm {...props} />
        </PhotosAuthShell>
    );
}

function TwoFactorVerifyPage(): React.JSX.Element {
    return <AccountsTwoFactorVerifyPage presentation={TwoFactorPresentation} />;
}

export default TwoFactorVerifyPage;
