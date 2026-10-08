import {
    isFamilyAdmin,
    isPartOfFamily,
    isSubscriptionPastDue,
    isSubscriptionStripe,
    redirectToCustomerPortal,
    type UserDetails,
} from "ente-new/photos/services/user-details";

export const openManageSubscription = ({
    userDetails,
    showManageMemberSubscription,
    onShowPlanSelector,
}: {
    userDetails: UserDetails | undefined;
    showManageMemberSubscription: () => void;
    onShowPlanSelector: () => void;
}) => {
    if (
        userDetails &&
        isPartOfFamily(userDetails) &&
        !isFamilyAdmin(userDetails)
    ) {
        showManageMemberSubscription();
    } else if (
        userDetails &&
        isSubscriptionStripe(userDetails.subscription) &&
        isSubscriptionPastDue(userDetails.subscription)
    ) {
        // TODO: This makes an API request, so the UI should indicate the await.
        //
        // eslint-disable-next-line @typescript-eslint/no-floating-promises
        redirectToCustomerPortal();
    } else {
        onShowPlanSelector();
    }
};
