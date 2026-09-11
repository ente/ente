import TwoFactorSetupPage from "ente-accounts/pages/two-factor/setup";
import { encryptWithPreloginRecoveryKey } from "ente-accounts/services/recovery-key";

export default function Page() {
    return (
        <TwoFactorSetupPage
            encryptWithRecoveryKey={encryptWithPreloginRecoveryKey}
        />
    );
}
