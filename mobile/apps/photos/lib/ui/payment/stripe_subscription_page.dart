import 'dart:async';

import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/subscription_purchased_event.dart";
import 'package:photos/gateways/billing/models/billing_plan.dart';
import 'package:photos/gateways/billing/models/subscription.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/user_details.dart';
import "package:photos/service_locator.dart";
import 'package:photos/services/account/user_service.dart';
import "package:photos/theme/colors.dart";
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/common/loading_widget.dart';
import 'package:photos/ui/common/progress_dialog.dart';
import 'package:photos/ui/common/web_page.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/components/buttons/button_widget_v2.dart';
import "package:photos/ui/components/menu_item_widget/menu_item_widget_new.dart";
import 'package:photos/ui/family/family_plan_page.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/ui/payment/payment_web_page.dart';
import 'package:photos/ui/payment/subscription_common_widgets.dart';
import 'package:photos/ui/payment/subscription_plan_widget.dart';
import "package:photos/ui/payment/view_add_on_widget.dart";
import 'package:photos/utils/dialog_util.dart';
import 'package:url_launcher/url_launcher_string.dart';

class StripeSubscriptionPage extends StatefulWidget {
  final bool isOnboarding;

  const StripeSubscriptionPage({this.isOnboarding = false, super.key});

  @override
  State<StripeSubscriptionPage> createState() => _StripeSubscriptionPageState();
}

class _StripeSubscriptionPageState extends State<StripeSubscriptionPage> {
  late final _billingService = billingService;
  final _userService = UserService.instance;
  Subscription? _currentSubscription;
  late ProgressDialog _dialog;
  late UserDetails _userDetails;

  // indicates if user's subscription plan is still active
  late bool _hasActiveSubscription;
  bool _hideCurrentPlanSelection = false;
  late FreePlan _freePlan;
  List<BillingPlan> _plans = [];
  bool _hasLoadedData = false;
  bool _isLoading = false;
  bool _isStripeSubscriber = false;
  bool _showYearlyPlan = false;
  EnteColorScheme colorScheme = darkScheme;
  final Logger logger = Logger("StripeSubscriptionPage");
  String? _selectedPlanProductID;

  Future<void> _fetchSub() async {
    return _userService.getUserDetailsV2(memoryCount: false).then((
      userDetails,
    ) async {
      _userDetails = userDetails;
      _currentSubscription = userDetails.subscription;

      if (_userDetails.isPartOfFamily() && !_userDetails.isFamilyAdmin()) {
        if (mounted) {
          replacePage(
            context,
            FamilyPlanPage(
              initialUserDetails: _userDetails,
              refreshOnOpen: false,
            ),
          );
        }
        return;
      }

      _showYearlyPlan = _currentSubscription!.isYearlyPlan();
      _hideCurrentPlanSelection =
          (_currentSubscription?.attributes?.isCancelled ?? false) &&
          userDetails.hasPaidAddon();
      _hasActiveSubscription = _currentSubscription!.isValid();
      _isStripeSubscriber = _currentSubscription!.paymentProvider == stripe;

      if (_isStripeSubscriber && _currentSubscription!.isPastDue()) {
        _redirectToPaymentPortal();
      }

      return _filterStripeForUI().then((value) {
        if (!mounted) return;
        _syncOnboardingSelection();
        _hasLoadedData = true;
        setState(() {});
      });
    });
  }

  // _filterPlansForUI is used for initializing initState & plan toggle states
  Future<void> _filterStripeForUI() async {
    final billingPlans = await _billingService.getBillingPlans();
    _freePlan = billingPlans.freePlan;
    _plans = billingPlans.plans.where((plan) {
      if (plan.id == freeProductID || plan.stripeID.isEmpty) {
        return false;
      }
      final isYearlyPlan = plan.period == 'year';
      return isYearlyPlan == _showYearlyPlan;
    }).toList();
    _syncOnboardingSelection();
    if (mounted) {
      setState(() {});
    }
  }

  FutureOr onWebPaymentGoBack(dynamic value) async {
    // refresh subscription
    await _dialog.show();
    try {
      await _fetchSub();
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        AppLocalizations.of(context).failedToRefreshStripeSubscription,
      );
    }
    await _dialog.hide();

    // verify user has subscribed before redirecting to main page
    if (widget.isOnboarding &&
        _currentSubscription != null &&
        _currentSubscription!.isValid() &&
        _currentSubscription!.productID != freeProductID) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colorScheme.backgroundColour,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: colorScheme.content,
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          widget.isOnboarding
              ? AppLocalizations.of(context).chooseYourPlan
              : AppLocalizations.of(context).subscription,
          style: textTheme.largeBold,
        ),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: _getBody())],
      ),
      bottomNavigationBar: widget.isOnboarding && _hasLoadedData
          ? Container(
              color: colorScheme.backgroundColour,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  child: ButtonWidgetV2(
                    buttonType: ButtonTypeV2.primary,
                    labelText: AppLocalizations.of(context).continueLabel,
                    isDisabled: _selectedPlanProductID == null,
                    onTap: _selectedPlanProductID == null
                        ? null
                        : _onOnboardingContinueTap,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _getBody() {
    if (!_isLoading) {
      _isLoading = true;
      _dialog = createProgressDialog(
        context,
        AppLocalizations.of(context).pleaseWait,
      );
      _fetchSub();
    }
    if (_hasLoadedData) {
      return _buildPlans();
    }
    return const EnteLoadingWidget();
  }

  Widget _buildPlans() {
    final widgets = <Widget>[];

    widgets.add(
      SubscriptionToggle(
        isYearly: _showYearlyPlan,
        onToggle: (p0) {
          _showYearlyPlan = p0;
          _filterStripeForUI();
        },
      ),
    );

    widgets.addAll([
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: _getStripePlanWidgets(),
      ),
    ]);

    final hasAddOnBonus =
        _userDetails.bonusData?.getAddOnBonuses().isNotEmpty ?? false;
    final shouldShowValidity =
        _currentSubscription != null &&
        (!_currentSubscription!.isFreePlan() || hasAddOnBonus);
    if (shouldShowValidity) {
      widgets.add(
        ValidityWidget(
          currentSubscription: _currentSubscription,
          bonusData: _userDetails.bonusData,
        ),
      );
      widgets.add(const SizedBox(height: 8));
    }

    if (_currentSubscription!.productID == freeProductID) {
      widgets.add(SubFaqWidget(isOnboarding: widget.isOnboarding));
      if (!widget.isOnboarding) {
        widgets.add(const SizedBox(height: 8));
      }
    }

    if (!widget.isOnboarding) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: MenuItemWidgetNew(
            title: AppLocalizations.of(context).manageFamily,
            menuItemColor: colorScheme.fillFaint,
            pressedColor: colorScheme.fillFaintPressed,
            trailingWidget: Icon(
              Icons.chevron_right_outlined,
              color: colorScheme.strokeBase,
            ),
            onTap: () async {
              late final UserDetails userDetails;
              try {
                userDetails = await _userService.getUserDetailsV2(
                  memoryCount: false,
                );
              } catch (error) {
                if (!context.mounted) {
                  return;
                }
                if (!mounted) return;
                await showGenericErrorDialog(context: context, error: error);
                return;
              }
              if (!context.mounted) {
                return;
              }
              if (!mounted) return;
              await _billingService.launchFamilyPortal(
                context,
                userDetails,
                popOnFreeAdvertViewPlans: true,
                refreshOnOpen: false,
              );
            },
          ),
        ),
      );
      widgets.add(ViewAddOnButton(_userDetails.bonusData));
    }

    if (_currentSubscription!.productID != freeProductID) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: MenuItemWidgetNew(
            title: "Manage payment method",
            menuItemColor: colorScheme.fillFaint,
            pressedColor: colorScheme.fillFaintPressed,
            trailingWidget: Icon(
              Icons.chevron_right_outlined,
              color: colorScheme.strokeBase,
            ),
            onTap: () async {
              _redirectToPaymentPortal();
            },
          ),
        ),
      );
    }

    // only active subscription can be renewed/canceled
    if (_hasActiveSubscription && _isStripeSubscriber) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _stripeRenewOrCancelButton(),
        ),
      );
    }

    widgets.add(const SizedBox(height: 80));

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: widgets,
      ),
    );
  }

  // _redirectToPaymentPortal action allows the user to update
  // their stripe payment details
  void _redirectToPaymentPortal() async {
    final String paymentProvider = _currentSubscription!.paymentProvider;
    switch (_currentSubscription!.paymentProvider) {
      case stripe:
        await _launchStripePortal();
        break;
      case playStore:
        unawaited(
          launchUrlString(
            "https://play.google.com/store/account/subscriptions?sku=" +
                _currentSubscription!.productID +
                "&package=io.ente.photos",
          ),
        );
        break;
      case appStore:
        unawaited(launchUrlString("https://apps.apple.com/account/billing"));
        break;
      default:
        final String capitalizedWord = paymentProvider.isNotEmpty
            ? '${paymentProvider[0].toUpperCase()}${paymentProvider.substring(1).toLowerCase()}'
            : '';
        await showErrorDialog(
          context,
          AppLocalizations.of(context).sorry,
          AppLocalizations.of(
            context,
          ).contactToManageSubscription(provider: capitalizedWord),
        );
    }
  }

  Future<void> _launchStripePortal() async {
    await _dialog.show();
    try {
      final String url = await _billingService.getStripeCustomerPortalUrl();
      await _dialog.hide();
      if (!mounted) return;
      await Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (BuildContext context) {
                return WebPage(
                  AppLocalizations.of(context).paymentDetails,
                  url,
                );
              },
            ),
          )
          .then((value) => onWebPaymentGoBack);
    } catch (e) {
      await _dialog.hide();
      if (!mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Widget _stripeRenewOrCancelButton() {
    final bool isRenewCancelled =
        _currentSubscription!.attributes?.isCancelled ?? false;
    if (isRenewCancelled && _userDetails.hasPaidAddon()) {
      return const SizedBox.shrink();
    }
    final String title = isRenewCancelled
        ? AppLocalizations.of(context).renewSubscription
        : AppLocalizations.of(context).cancelSubscription;
    return MenuItemWidgetNew(
      title: title,
      alwaysShowSuccessState: false,
      surfaceExecutionStates: false,
      menuItemColor: colorScheme.fillFaint,
      pressedColor: colorScheme.fillFaintPressed,
      trailingWidget: Icon(
        Icons.chevron_right_outlined,
        color: colorScheme.strokeBase,
      ),
      onTap: () async {
        bool confirmAction = false;
        if (isRenewCancelled) {
          final choice = await showChoiceDialog(
            context,
            title: title,
            body: AppLocalizations.of(context).areYouSureYouWantToRenew,
            firstButtonLabel: AppLocalizations.of(context).yesRenew,
          );
          confirmAction = choice!.action == ButtonAction.first;
        } else {
          final choice = await showChoiceDialog(
            context,
            title: title,
            body: AppLocalizations.of(context).areYouSureYouWantToCancel,
            firstButtonLabel: AppLocalizations.of(context).yesCancel,
            secondButtonLabel: AppLocalizations.of(context).no,
            isCritical: true,
          );
          confirmAction = choice!.action == ButtonAction.first;
        }
        if (confirmAction) {
          await toggleStripeSubscription(isRenewCancelled);
        }
      },
    );
  }

  // toggleStripeSubscription, based on current auto renew status, will
  // toggle the auto renew status of the user's subscription
  Future<void> toggleStripeSubscription(bool isAutoRenewDisabled) async {
    await _dialog.show();
    try {
      isAutoRenewDisabled
          ? await _billingService.activateStripeSubscription()
          : await _billingService.cancelStripeSubscription();
      await _fetchSub();
    } catch (e) {
      if (!mounted) return;
      showShortToast(
        context,
        isAutoRenewDisabled
            ? AppLocalizations.of(context).failedToRenew
            : AppLocalizations.of(context).failedToCancel,
      );
    }
    await _dialog.hide();
    if (!isAutoRenewDisabled && mounted) {
      await showTextInputDialog(
        context,
        title: AppLocalizations.of(context).askCancelReason,
        submitButtonLabel: AppLocalizations.of(context).send,
        hintText: AppLocalizations.of(context).optionalAsShortAsYouLike,
        alwaysShowSuccessState: true,
        textCapitalization: TextCapitalization.words,
        onSubmit: (String text) async {
          // indicates user cancelled the rename request
          if (text == "" || text.trim().isEmpty) {
            return;
          }
          try {
            await UserService.instance.sendFeedback(context, text);
          } catch (e, s) {
            logger.severe("Failed to send feedback", e, s);
          }
        },
      );
    }
  }

  List<Widget> _getStripePlanWidgets() {
    final List<Widget> planWidgets = [];
    if (_shouldShowFreePlanCard()) {
      planWidgets.add(
        GestureDetector(
          onTap: () {
            if (!widget.isOnboarding) {
              return;
            }
            setState(() {
              _selectedPlanProductID = freeProductID;
            });
          },
          child: SubscriptionPlanWidget(
            storage: _freePlan.storage,
            price: "",
            period: AppLocalizations.of(context).freeTrial,
            isActive: widget.isOnboarding
                ? _selectedPlanProductID == freeProductID
                : _isFreePlanUser(),
            isOnboarding: widget.isOnboarding,
          ),
        ),
      );
    }

    for (final plan in _plans) {
      final productID = plan.stripeID;
      if (productID.isEmpty) {
        continue;
      }
      final isActive =
          _hasActiveSubscription &&
          _currentSubscription!.productID == productID;
      planWidgets.add(
        GestureDetector(
          onTap: () async {
            if (widget.isOnboarding) {
              setState(() {
                _selectedPlanProductID = productID;
              });
              return;
            }
            if (isActive) {
              return;
            }
            // prompt user to cancel their active subscription form other
            // payment providers
            if (!_isStripeSubscriber &&
                _hasActiveSubscription &&
                _currentSubscription!.productID != freeProductID) {
              await showErrorDialog(
                context,
                AppLocalizations.of(context).sorry,
                AppLocalizations.of(context).cancelOtherSubscription(
                  paymentProvider: _currentSubscription!.paymentProvider,
                ),
              );
              return;
            }
            final int addOnBonus =
                _userDetails.bonusData?.totalAddOnBonus() ?? 0;
            if (_userDetails.getFamilyOrPersonalUsage() >
                (plan.storage + addOnBonus)) {
              logger.warning(
                " familyUsage ${convertBytesToReadableFormat(_userDetails.getFamilyOrPersonalUsage())}"
                " plan storage ${convertBytesToReadableFormat(plan.storage)} "
                "addOnBonus ${convertBytesToReadableFormat(addOnBonus)},"
                "overshooting by ${convertBytesToReadableFormat(_userDetails.getFamilyOrPersonalUsage() - (plan.storage + addOnBonus))}",
              );
              await showErrorDialog(
                context,
                AppLocalizations.of(context).sorry,
                AppLocalizations.of(context).youCannotDowngradeToThisPlan,
              );
              return;
            }
            String stripPurChaseAction = 'buy';
            if (_isStripeSubscriber && _hasActiveSubscription) {
              // confirm if user wants to change plan or not
              final result = await showChoiceDialog(
                context,
                title: AppLocalizations.of(context).confirmPlanChange,
                body: AppLocalizations.of(
                  context,
                ).areYouSureYouWantToChangeYourPlan,
                firstButtonLabel: AppLocalizations.of(context).yes,
              );
              if (result?.action == ButtonAction.first) {
                stripPurChaseAction = 'update';
              } else {
                return;
              }
            }
            if (!mounted) return;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (BuildContext context) {
                  return PaymentWebPage(
                    planId: plan.stripeID,
                    actionType: stripPurChaseAction,
                  );
                },
              ),
            ).then((value) => onWebPaymentGoBack(value));
          },
          child: SubscriptionPlanWidget(
            storage: plan.storage,
            price: plan.price,
            period: plan.period,
            isActive: widget.isOnboarding
                ? _selectedPlanProductID == productID
                : isActive && !_hideCurrentPlanSelection,
            isPopular: _isPopularPlan(plan),
            isOnboarding: widget.isOnboarding,
          ),
        ),
      );
    }
    return planWidgets;
  }

  bool _isPopularPlan(BillingPlan plan) {
    return popularProductIDs.contains(plan.id);
  }

  bool _isFreePlanUser() {
    return _currentSubscription != null &&
        _currentSubscription!.productID == freeProductID;
  }

  bool _shouldShowFreePlanCard() {
    return widget.isOnboarding || _isFreePlanUser();
  }

  void _syncOnboardingSelection() {
    if (!widget.isOnboarding) {
      return;
    }
    final visibleProductIDs = _plans
        .map((plan) => plan.stripeID)
        .where((id) => id.isNotEmpty)
        .toSet();
    final hasFreeOptionVisible = _shouldShowFreePlanCard();

    if (_selectedPlanProductID == freeProductID && hasFreeOptionVisible) {
      return;
    }
    if (_selectedPlanProductID != null &&
        visibleProductIDs.contains(_selectedPlanProductID)) {
      return;
    }
    final currentProductID = _currentSubscription?.productID;
    if (currentProductID != null &&
        visibleProductIDs.contains(currentProductID)) {
      _selectedPlanProductID = currentProductID;
      return;
    }
    if (hasFreeOptionVisible) {
      _selectedPlanProductID = freeProductID;
      return;
    }
    _selectedPlanProductID = visibleProductIDs.isNotEmpty
        ? visibleProductIDs.first
        : null;
  }

  Future<void> _onOnboardingContinueTap() async {
    final selectedPlanProductID = _selectedPlanProductID;
    if (selectedPlanProductID == null) {
      return;
    }

    if (selectedPlanProductID == freeProductID) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      Bus.instance.fire(SubscriptionPurchasedEvent());
      unawaited(
        _billingService.verifySubscription(
          freeProductID,
          "",
          paymentProvider: "ente",
        ),
      );
      return;
    }

    final BillingPlan? selectedPlan = _plans
        .where((plan) => plan.stripeID == selectedPlanProductID)
        .firstOrNull;
    if (selectedPlan == null) {
      return;
    }

    final isActive =
        _hasActiveSubscription &&
        _currentSubscription!.productID == selectedPlanProductID;
    if (isActive) {
      return;
    }

    if (!_isStripeSubscriber &&
        _hasActiveSubscription &&
        _currentSubscription!.productID != freeProductID) {
      await showErrorDialog(
        context,
        AppLocalizations.of(context).sorry,
        AppLocalizations.of(context).cancelOtherSubscription(
          paymentProvider: _currentSubscription!.paymentProvider,
        ),
      );
      return;
    }

    final int addOnBonus = _userDetails.bonusData?.totalAddOnBonus() ?? 0;
    if (_userDetails.getFamilyOrPersonalUsage() >
        (selectedPlan.storage + addOnBonus)) {
      logger.warning(
        " familyUsage ${convertBytesToReadableFormat(_userDetails.getFamilyOrPersonalUsage())}"
        " plan storage ${convertBytesToReadableFormat(selectedPlan.storage)} "
        "addOnBonus ${convertBytesToReadableFormat(addOnBonus)},"
        "overshooting by ${convertBytesToReadableFormat(_userDetails.getFamilyOrPersonalUsage() - (selectedPlan.storage + addOnBonus))}",
      );
      await showErrorDialog(
        context,
        AppLocalizations.of(context).sorry,
        AppLocalizations.of(context).youCannotDowngradeToThisPlan,
      );
      return;
    }

    String stripPurChaseAction = 'buy';
    if (_isStripeSubscriber && _hasActiveSubscription) {
      final result = await showChoiceDialog(
        context,
        title: AppLocalizations.of(context).confirmPlanChange,
        body: AppLocalizations.of(context).areYouSureYouWantToChangeYourPlan,
        firstButtonLabel: AppLocalizations.of(context).yes,
      );
      if (result!.action == ButtonAction.first) {
        stripPurChaseAction = 'update';
      } else {
        return;
      }
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (BuildContext context) {
          return PaymentWebPage(
            planId: selectedPlan.stripeID,
            actionType: stripPurChaseAction,
          );
        },
      ),
    ).then((value) => onWebPaymentGoBack(value));
  }
}
