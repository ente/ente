import { errorDialogAttributes } from "ente-base/components/utils/dialog";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { haveMasterKeyInSession } from "ente-base/session-storage";
import {
    redirectToCustomerPortal,
    verifyStripeSubscription,
} from "ente-new/photos/services/user-details";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import { useRouter } from "next/router";
import { useEffect, useEffectEvent } from "react";
import { Trans } from "react-i18next";

export const useSubscriptionCompletionRedirect = () => {
    const router = useRouter();
    const { showMiniDialog } = useBaseContext();
    const { showLoadingBar } = usePhotosAppContext();

    const handleCompletion = useEffectEvent(async () => {
        const { session_id: sessionID, status, reason } = router.query;

        if (status == "success") {
            try {
                const subscription = await verifyStripeSubscription(sessionID);
                showMiniDialog({
                    title: t("thank_you"),
                    message: (
                        <Trans
                            i18nKey="subscription_purchase_success"
                            values={{ date: subscription.expiryTime }}
                        />
                    ),
                    continue: { text: t("ok") },
                    cancel: false,
                });
            } catch (e) {
                log.error("Subscription verification failed", e);
                showMiniDialog(
                    errorDialogAttributes(t("subscription_verification_error")),
                );
            }
        } else if (status == "fail") {
            log.error(`Subscription purchase failed`, reason);
            switch (reason) {
                case "canceled":
                    showMiniDialog({
                        message: t("subscription_purchase_cancelled"),
                        continue: { text: t("ok"), color: "primary" },
                        cancel: false,
                    });
                    break;
                case "requires_payment_method":
                case "authentication_failed":
                    showMiniDialog({
                        title: t("update_payment_method"),
                        message:
                            reason == "authentication_failed"
                                ? t("payment_method_authentication_failed")
                                : t("update_payment_method_message"),
                        continue: {
                            text: t("update_payment_method"),
                            action: () => {
                                showLoadingBar();
                                return redirectToCustomerPortal();
                            },
                        },
                    });
                    break;
                default:
                    showMiniDialog(
                        errorDialogAttributes(
                            t("subscription_purchase_failed"),
                        ),
                    );
            }
        }
    });

    useEffect(() => {
        if (router.isReady && haveMasterKeyInSession()) {
            void handleCompletion();
        }
    }, [router.isReady]);
};
