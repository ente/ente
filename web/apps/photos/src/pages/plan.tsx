import { PhotosAuthShell } from "@/components/PhotosAuthShell";
import { PlanSelectorContents } from "@/components/PlanSelector";
import {
    getAndClearJustSignedUp,
    savedJustSignedUp,
} from "ente-accounts/services/accounts-db";
import {
    LoadingIndicator,
    TranslucentLoadingOverlay,
} from "ente-base/components/loaders";
import { haveMasterKeyInSession } from "ente-base/session-storage";
import { savedAuthToken } from "ente-base/token";
import { useRouter } from "next/router";
import { useEffect, useState, type JSX } from "react";

function PlanPage(): JSX.Element {
    const router = useRouter();
    const [isReady, setIsReady] = useState(false);
    const [isLoading, setIsLoading] = useState(false);

    useEffect(() => {
        void (async () => {
            if (!haveMasterKeyInSession() || !(await savedAuthToken())) {
                await router.replace("/");
            } else if (!savedJustSignedUp()) {
                await router.replace("/gallery");
            } else {
                setIsReady(true);
            }
        })();
    }, [router]);

    function handleContinue() {
        getAndClearJustSignedUp();
        void router.push("/gallery");
    }

    function handleBeginCheckout() {
        getAndClearJustSignedUp();
    }

    if (!isReady) return <LoadingIndicator />;

    return (
        <>
            <PhotosAuthShell contentWidth={420}>
                <PlanSelectorContents
                    onClose={handleContinue}
                    setLoading={setIsLoading}
                    onManageFamily={handleContinue}
                    onBeginCheckout={handleBeginCheckout}
                />
            </PhotosAuthShell>
            {isLoading && <TranslucentLoadingOverlay />}
        </>
    );
}

export default PlanPage;
