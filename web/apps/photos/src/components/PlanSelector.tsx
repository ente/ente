import { PlanSelectionCards } from "@/components/PlanSelectionCards";
import { useWrapAsyncOperation } from "@/components/utils/use-wrap-async";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import { Dialog, Link, Stack, useMediaQuery, useTheme } from "@mui/material";
import Box from "@mui/material/Box";
import Typography from "@mui/material/Typography";
import type { ButtonishProps } from "ente-base/components/mui";
import { DialogCloseIconButton } from "ente-base/components/mui/DialogCloseIconButton";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { SidebarDrawer } from "ente-base/components/mui/SidebarDrawer";
import { SidebarPanelContext } from "ente-base/components/mui/SidebarDrawerContext";
import {
    errorDialogAttributes,
    genericRetriableErrorDialogAttributes,
} from "ente-base/components/utils/dialog";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { formattedStorageByteSize } from "ente-gallery/utils/units";
import { useUserDetailsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import type {
    Bonus,
    Plan,
    PlansData,
    Subscription,
} from "ente-new/photos/services/user-details";
import {
    activateStripeSubscription,
    cancelStripeSubscription,
    getPlansData,
    isFamilyAdmin,
    isPartOfFamily,
    isSubscriptionActivePaid,
    isSubscriptionCancelled,
    isSubscriptionForPlan,
    isSubscriptionFree,
    isSubscriptionStripe,
    planUsage,
    redirectToCustomerPortal,
    redirectToPaymentsApp,
    userDetailsAddOnBonuses,
} from "ente-new/photos/services/user-details";
import { t } from "i18next";
import React, { useContext, useEffect, useMemo, useState } from "react";
import { Trans } from "react-i18next";

type PlanSelectorProps = ModalVisibilityProps & {
    setLoading: (loading: boolean) => void;
    onManageFamily: () => void;
};

export const PlanSelector: React.FC<PlanSelectorProps> = ({
    open,
    onClose,
    setLoading,
    onManageFamily,
}) => {
    const fullScreen = useMediaQuery(useTheme().breakpoints.down("sm"));
    const sidebarPanel = useContext(SidebarPanelContext);

    if (!open) {
        return <></>;
    }

    if (sidebarPanel) {
        return (
            <SidebarDrawer {...{ open, onClose }} transitionDuration={0}>
                <Box sx={{ maxWidth: 420, mx: "auto", py: 1 }}>
                    <PlanSelectorContents
                        {...{ onClose, setLoading, onManageFamily }}
                    />
                </Box>
            </SidebarDrawer>
        );
    }

    return (
        <Dialog
            {...{ open, onClose, fullScreen }}
            slotProps={{
                paper: {
                    sx: (theme) => ({
                        width: { sm: "391px" },
                        p: 1,
                        [theme.breakpoints.down(360)]: { p: 0 },
                    }),
                },
                backdrop: { sx: { backdropFilter: "blur(30px) opacity(95%)" } },
            }}
        >
            <PlanSelectorContents
                {...{ onClose, setLoading, onManageFamily }}
            />
        </Dialog>
    );
};

export type PlanSelectorContentsProps = Pick<
    PlanSelectorProps,
    "onClose" | "setLoading" | "onManageFamily"
> & { variant?: "manage" | "signup"; onBeginCheckout?: () => void };

export const PlanSelectorContents: React.FC<PlanSelectorContentsProps> = ({
    onClose,
    setLoading,
    onManageFamily,
    variant = "manage",
    onBeginCheckout,
}) => {
    const { showMiniDialog } = useBaseContext();
    const showCloseButton = !useContext(SidebarPanelContext);

    const userDetails = useUserDetailsSnapshot();

    const [catalog, setCatalog] = useState<PlansData | undefined>();
    const usage = userDetails ? planUsage(userDetails) : 0;
    const subscription = userDetails?.subscription;
    const addOnBonuses = userDetails
        ? userDetailsAddOnBonuses(userDetails)
        : [];
    const activePaidSubscription =
        subscription && isSubscriptionActivePaid(subscription)
            ? subscription
            : undefined;
    const plansData = useMemo<PlansData | undefined>(() => {
        if (
            !catalog ||
            !activePaidSubscription ||
            catalog.plans.some((plan) =>
                isSubscriptionForPlan(activePaidSubscription, plan),
            )
        ) {
            return catalog;
        }
        const { productID, storage, price, period } = activePaidSubscription;
        return {
            ...catalog,
            plans: [
                ...catalog.plans,
                {
                    id: productID,
                    storage,
                    price,
                    period,
                    stripeID: productID,
                    iosID: productID,
                    androidID: productID,
                },
            ],
        };
    }, [activePaidSubscription, catalog]);

    useEffect(() => {
        const request = { cancelled: false };
        void (async () => {
            try {
                const plansData = await getPlansData();
                if (request.cancelled) return;
                setCatalog(plansData);
            } catch (e) {
                if (request.cancelled) return;
                log.error("Failed to get plans", e);
                onClose();
                showMiniDialog(genericRetriableErrorDialogAttributes());
            }
        })();
        return () => {
            request.cancelled = true;
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    const handlePlanSelect = async (plan: Plan) => {
        switch (planSelectionOutcome(subscription)) {
            case "buyPlan":
                try {
                    onBeginCheckout?.();
                    setLoading(true);
                    await redirectToPaymentsApp(plan.stripeID!, "buy");
                } catch (e) {
                    log.error(e);
                    setLoading(false);
                    showMiniDialog(
                        errorDialogAttributes(
                            t("subscription_purchase_failed"),
                        ),
                    );
                }
                break;

            case "updateSubscriptionToPlan":
                showMiniDialog({
                    title: t("update_subscription_title"),
                    message: t("update_subscription_message"),
                    continue: {
                        text: t("update_subscription"),
                        action: () =>
                            redirectToPaymentsApp(plan.stripeID!, "update"),
                    },
                });
                break;

            case "cancelOnMobile":
                showMiniDialog({
                    title: t("cancel_subscription_on_mobile"),
                    message: t("cancel_subscription_on_mobile_message"),
                    continue: {},
                    cancel: false,
                });
                break;

            case "contactSupport":
                showMiniDialog({
                    title: t("manage_plan"),
                    message: (
                        <Trans
                            i18nKey={"mail_to_manage_subscription"}
                            components={{
                                a: <Link href="mailto:support@ente.com" />,
                            }}
                            values={{ emailID: "support@ente.com" }}
                        />
                    ),
                    continue: {},
                    cancel: false,
                });
                break;
        }
    };

    if (variant === "signup") {
        return (
            <PlanSelectionCards
                plansData={plansData}
                showLockerAllowance
                onContinueFree={onClose}
                onContinuePaid={handlePlanSelect}
            />
        );
    }

    const currentPlanID = activePaidSubscription
        ? plansData?.plans.find((plan) =>
              isSubscriptionForPlan(activePaidSubscription, plan),
          )?.id
        : undefined;
    const canContinueFree =
        (!subscription || isSubscriptionFree(subscription)) &&
        !addOnBonuses.length;
    const isNonAdminFamilyMember =
        userDetails &&
        isPartOfFamily(userDetails) &&
        !isFamilyAdmin(userDetails);

    return (
        <Stack sx={{ gap: 2, p: 1.5 }}>
            {showCloseButton && (
                <Box sx={{ alignSelf: "flex-end" }}>
                    <DialogCloseIconButton onClose={onClose} />
                </Box>
            )}
            {activePaidSubscription && (
                <Typography sx={{ color: "text.muted" }}>
                    <Trans
                        i18nKey="current_usage"
                        values={{ usage: formattedStorageByteSize(usage) }}
                    />
                </Typography>
            )}
            <PlanSelectionCards
                plansData={plansData}
                initialPeriod={subscription?.period ?? "month"}
                currentPlanID={currentPlanID}
                listMaxHeight="clamp(120px, calc(100svh - 220px), 530px)"
                freePlanAction={isNonAdminFamilyMember ? "close" : "continue"}
                onContinueFree={canContinueFree ? onClose : undefined}
                onContinuePaid={handlePlanSelect}
            />
            {subscription &&
                (activePaidSubscription || addOnBonuses.length > 0) && (
                    <>
                        <Stack sx={{ gap: 1.5 }}>
                            {activePaidSubscription && (
                                <Typography sx={{ color: "text.muted" }}>
                                    {t(
                                        isSubscriptionCancelled(
                                            activePaidSubscription,
                                        )
                                            ? "subscription_status_renewal_cancelled"
                                            : "subscription_status_renewal_active",
                                        {
                                            date: activePaidSubscription.expiryTime,
                                        },
                                    )}
                                </Typography>
                            )}
                            <AddOnBonusRows addOnBonuses={addOnBonuses} />
                        </Stack>
                        <ManageSubscription
                            {...{ onClose, onManageFamily, subscription }}
                            hasAddOnBonus={addOnBonuses.length > 0}
                        />
                    </>
                )}
        </Stack>
    );
};

const planSelectionOutcome = (subscription: Subscription | undefined) => {
    if (!subscription) return "buyPlan";

    if (subscription.productID == "free") return "buyPlan";

    if (subscription.expiryTime < Date.now() * 1000) return "buyPlan";

    if (subscription.paymentProvider == "stripe") {
        return "updateSubscriptionToPlan";
    }

    if (
        subscription.paymentProvider == "appstore" ||
        subscription.paymentProvider == "playstore"
    ) {
        return "cancelOnMobile";
    }

    return "contactSupport";
};

interface AddOnBonusRowsProps {
    addOnBonuses: Bonus[];
}

const AddOnBonusRows: React.FC<AddOnBonusRowsProps> = ({ addOnBonuses }) => (
    <>
        {addOnBonuses.map((bonus, i) => (
            <Typography key={i} variant="small" sx={{ color: "text.muted" }}>
                <Trans
                    i18nKey={"add_on_valid_till"}
                    values={{
                        storage: formattedStorageByteSize(bonus.storage),
                        date: bonus.validTill,
                    }}
                />
            </Typography>
        ))}
    </>
);

type ManageSubscriptionProps = Pick<
    PlanSelectorProps,
    "onClose" | "onManageFamily"
> & { subscription: Subscription; hasAddOnBonus: boolean };

function ManageSubscription({
    onClose,
    onManageFamily,
    subscription,
    hasAddOnBonus,
}: ManageSubscriptionProps) {
    const manageFamily = () => {
        onClose();
        onManageFamily();
    };

    return (
        <Stack sx={{ gap: 1 }}>
            {isSubscriptionStripe(subscription) && (
                <StripeSubscriptionOptions
                    {...{ onClose, subscription, hasAddOnBonus }}
                />
            )}
            <ManageSubscriptionButton onClick={manageFamily}>
                {t("manage_family")}
            </ManageSubscriptionButton>
        </Stack>
    );
}

type StripeSubscriptionOptionsProps = Pick<PlanSelectorProps, "onClose"> & {
    subscription: Subscription;
    hasAddOnBonus: boolean;
};

const StripeSubscriptionOptions: React.FC<StripeSubscriptionOptionsProps> = ({
    onClose,
    subscription,
    hasAddOnBonus,
}) => {
    const { showMiniDialog } = useBaseContext();

    const confirmReactivation = () =>
        showMiniDialog({
            title: t("reactivate_subscription"),
            message: t("reactivate_subscription_message", {
                date: subscription.expiryTime,
            }),
            continue: {
                text: t("reactivate_subscription"),
                action: async () => {
                    await activateStripeSubscription();
                    onClose();
                    // Wait for this action's dialog to close before showing another.
                    setTimeout(() => {
                        showMiniDialog({
                            title: t("success"),
                            message: t("subscription_activate_success"),
                            continue: { action: onClose },
                            cancel: false,
                        });
                    }, 0);
                },
            },
        });

    const confirmCancel = () =>
        showMiniDialog({
            title: t("cancel_subscription"),
            message: hasAddOnBonus ? (
                <Trans i18nKey={"cancel_subscription_with_addon_message"} />
            ) : (
                <Trans i18nKey={"cancel_subscription_message"} />
            ),
            continue: {
                text: t("cancel_subscription"),
                color: "critical",
                action: async () => {
                    await cancelStripeSubscription();
                    onClose();
                    // Wait for this action's dialog to close before showing another.
                    setTimeout(() => {
                        showMiniDialog({
                            message: t("subscription_cancel_success"),
                            cancel: t("ok"),
                        });
                    }, 0);
                },
            },
            cancel: t("nevermind"),
        });

    const handleManageClick = useWrapAsyncOperation(redirectToCustomerPortal);

    return (
        <>
            {isSubscriptionCancelled(subscription) ? (
                <ManageSubscriptionButton onClick={confirmReactivation}>
                    {t("reactivate_subscription")}
                </ManageSubscriptionButton>
            ) : (
                <ManageSubscriptionButton onClick={confirmCancel}>
                    {t("cancel_subscription")}
                </ManageSubscriptionButton>
            )}
            <ManageSubscriptionButton onClick={handleManageClick}>
                {t("manage_payment_method")}
            </ManageSubscriptionButton>
        </>
    );
};

const ManageSubscriptionButton: React.FC<
    React.PropsWithChildren<ButtonishProps>
> = ({ onClick, children }) => (
    <FocusVisibleButton
        fullWidth
        color="secondary"
        endIcon={<ChevronRightIcon />}
        {...{ onClick }}
    >
        <Box sx={{ flex: 1, textAlign: "left" }}>{children}</Box>
    </FocusVisibleButton>
);
