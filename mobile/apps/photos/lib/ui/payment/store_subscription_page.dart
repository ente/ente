import 'dart:async';
import 'dart:io';

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:logging/logging.dart';
import "package:photos/core/constants.dart";
import 'package:photos/core/errors.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/subscription_purchased_event.dart';
import 'package:photos/gateways/billing/models/billing_plan.dart';
import 'package:photos/gateways/billing/models/subscription.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/user_details.dart';
import "package:photos/service_locator.dart";
import 'package:photos/services/account/user_service.dart';
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import 'package:photos/ui/common/loading_widget.dart';
import 'package:photos/ui/common/progress_dialog.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/components/buttons/button_widget_v2.dart';
import 'package:photos/ui/components/dialog_widget.dart';
import "package:photos/ui/components/menu_item_widget/menu_item_widget_new.dart";
import 'package:photos/ui/components/models/button_type.dart';
import 'package:photos/ui/family/family_plan_page.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/ui/payment/subscription_common_widgets.dart';
import 'package:photos/ui/payment/subscription_plan_widget.dart';
import "package:photos/ui/payment/view_add_on_widget.dart";
import 'package:photos/utils/dialog_util.dart';
import 'package:photos/utils/email_util.dart';
import 'package:url_launcher/url_launcher_string.dart';

class StoreSubscriptionPage extends StatefulWidget {
  final bool isOnboarding;

  const StoreSubscriptionPage({this.isOnboarding = false, super.key});

  @override
  State<StoreSubscriptionPage> createState() => _StoreSubscriptionPageState();
}

class _StoreSubscriptionPageState extends State<StoreSubscriptionPage> {
  final _logger = Logger("SubscriptionPage");
  late final _billingService = billingService;
  final _userService = UserService.instance;
  Subscription? _currentSubscription;
  late StreamSubscription _purchaseUpdateSubscription;
  late ProgressDialog _dialog;
  late UserDetails _userDetails;
  late bool _hasActiveSubscription;
  bool _hideCurrentPlanSelection = false;
  late FreePlan _freePlan;
  late List<BillingPlan> _plans;
  bool _hasLoadedData = false;
  bool _isLoading = false;
  late bool _isActiveStripeSubscriber;
  EnteColorScheme colorScheme = darkScheme;
  String? _selectedProductID;

  // hasYearlyPlans is used to check if there are yearly plans for given store
  bool hasYearlyPlans = false;

  // _showYearlyPlan is used to determine if we should show the yearly plans
  bool showYearlyPlan = false;

  @override
  void initState() {
    super.initState();
    _billingService.setIsOnSubscriptionPage(true);
    _setupPurchaseUpdateStreamListener();
  }

  void _setupPurchaseUpdateStreamListener() {
    _purchaseUpdateSubscription = InAppPurchase.instance.purchaseStream.listen((
      purchases,
    ) async {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      if (!_dialog.isShowing()) {
        await _dialog.show();
      }
      if (!mounted) {
        await _dialog.hide();
        return;
      }
      for (final purchase in purchases) {
        _logger.info("Purchase status " + purchase.status.toString());
        if (purchase.status == PurchaseStatus.purchased) {
          try {
            final newSubscription = await _billingService.verifySubscription(
              purchase.productID,
              purchase.verificationData.serverVerificationData,
            );
            await InAppPurchase.instance.completePurchase(purchase);
            final wasActiveSubscription = _hasActiveSubscription;
            final previousSubscription = _currentSubscription;
            _currentSubscription = newSubscription;
            _hasActiveSubscription = _currentSubscription!.isValid();
            Bus.instance.fire(SubscriptionPurchasedEvent());
            if (mounted) {
              String text = l10n.thankYouForSubscribing;
              if (!widget.isOnboarding && previousSubscription != null) {
                final isUpgrade =
                    wasActiveSubscription &&
                    newSubscription.storage > previousSubscription.storage;
                final isDowngrade =
                    wasActiveSubscription &&
                    newSubscription.storage < previousSubscription.storage;
                if (isUpgrade) {
                  text = l10n.yourPlanWasSuccessfullyUpgraded;
                } else if (isDowngrade) {
                  text = l10n.yourPlanWasSuccessfullyDowngraded;
                }
              }
              showShortToast(context, text);
              setState(() {});
              await _dialog.hide();
            }
            if (mounted && widget.isOnboarding) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          } on SubscriptionAlreadyClaimedError catch (e) {
            _logger.warning("subscription is already claimed ", e);
            await _dialog.hide();
            if (!mounted) return;
            final String title = Platform.isAndroid
                ? l10n.playstoreSubscription
                : l10n.appstoreSubscription;
            final String id = Platform.isAndroid
                ? l10n.googlePlayId
                : l10n.appleId;
            final String message = l10n.subAlreadyLinkedErrMessage(id: id);
            await showDialogWidget(
              context: context,
              title: title,
              body: message,
              buttons: [
                ButtonWidget(
                  buttonType: ButtonType.primary,
                  labelText: l10n.contactSupport,
                  buttonAction: ButtonAction.first,
                  isInAlert: true,
                  onTap: () async {
                    await sendLogs(
                      context,
                      l10n.contactSupport,
                      "support@ente.com",
                      postShare: () {},
                    );
                  },
                ),
                ButtonWidget(
                  buttonType: ButtonType.secondary,
                  labelText: l10n.cancel,
                  buttonAction: ButtonAction.cancel,
                  isInAlert: true,
                ),
              ],
            );
            return;
          } catch (e) {
            _logger.warning("Could not complete payment ", e);
            await _dialog.hide();
            if (!mounted) return;
            // ignore: unawaited_futures
            showErrorDialog(
              context,
              l10n.paymentFailed,
              l10n.paymentFailedTalkToProvider(
                providerName: Platform.isAndroid ? "PlayStore" : "AppStore",
              ),
            );
            return;
          }
        } else if (Platform.isIOS && purchase.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchase);
          await _dialog.hide();
        } else if (purchase.status == PurchaseStatus.error) {
          await _dialog.hide();
        }
      }
    });
  }

  @override
  void dispose() {
    _purchaseUpdateSubscription.cancel();
    _billingService.setIsOnSubscriptionPage(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    colorScheme = getEnteColorScheme(context);
    if (!_isLoading) {
      _isLoading = true;
      _fetchSubData();
    }
    _dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).pleaseWait,
      isDismissible: true,
    );
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
              : "${AppLocalizations.of(context).subscription}${kDebugMode ? ' Store' : ''}",
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
                    isDisabled: _selectedProductID == null,
                    onTap: _selectedProductID == null
                        ? null
                        : _onOnboardingContinueTap,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  bool _isFreePlanUser() {
    return _currentSubscription != null &&
        freeProductID == _currentSubscription!.productID;
  }

  bool _shouldShowFreePlanCard() {
    return widget.isOnboarding || _isFreePlanUser();
  }

  Future<void> _fetchSubData() async {
    try {
      final userDetails = await _userService.getUserDetailsV2(
        memoryCount: false,
      );
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

      _hasActiveSubscription = _currentSubscription!.isValid();
      _hideCurrentPlanSelection =
          _currentSubscription?.attributes?.isCancelled ?? false;
      showYearlyPlan = _currentSubscription!.isYearlyPlan();
      final billingPlans = await _billingService.getBillingPlans();
      _isActiveStripeSubscriber =
          _currentSubscription!.paymentProvider == stripe &&
          _currentSubscription!.isValid();
      _plans = billingPlans.plans.where((plan) {
        final productID = _isActiveStripeSubscriber
            ? plan.stripeID
            : Platform.isAndroid
            ? plan.androidID
            : plan.iosID;
        return plan.id != freeProductID && productID.isNotEmpty;
      }).toList();
      hasYearlyPlans = _plans.any((plan) => plan.period == 'year');
      if (showYearlyPlan && hasYearlyPlans) {
        _plans = _plans.where((plan) => plan.period == 'year').toList();
      } else {
        _plans = _plans.where((plan) => plan.period != 'year').toList();
      }
      _freePlan = billingPlans.freePlan;
      _syncOnboardingSelection();
      _hasLoadedData = true;
      if (mounted) {
        setState(() {});
      }
    } catch (e, s) {
      _logger.severe("Error fetching subscription data", e, s);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _getBody() {
    if (_hasLoadedData) {
      return _buildPlans();
    }
    return const EnteLoadingWidget();
  }

  Widget _buildPlans() {
    final widgets = <Widget>[];

    if (hasYearlyPlans) {
      widgets.add(
        SubscriptionToggle(
          isYearly: showYearlyPlan,
          onToggle: (p0) {
            showYearlyPlan = p0;
            _filterStorePlansForUi();
          },
        ),
      );
    }

    widgets.addAll([
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: _isActiveStripeSubscriber
            ? _getStripePlanWidgets()
            : _getMobilePlanWidgets(),
      ),
    ]);

    if (_currentSubscription != null) {
      widgets.add(
        ValidityWidget(
          currentSubscription: _currentSubscription,
          bonusData: _userDetails.bonusData,
        ),
      );
    }

    if (_hasActiveSubscription &&
        _currentSubscription!.productID != freeProductID) {
      if (_isActiveStripeSubscriber) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
            child: Text(
              AppLocalizations.of(
                context,
              ).visitWebToManage(webUrl: kPhotosWebDomain),
              style: getEnteTextTheme(
                context,
              ).small.copyWith(color: colorScheme.textMuted),
            ),
          ),
        );
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: MenuItemWidgetNew(
              title: AppLocalizations.of(context).managePaymentMethod,
              menuItemColor: colorScheme.fillFaint,
              pressedColor: colorScheme.fillFaintPressed,
              trailingWidget: Icon(
                Icons.chevron_right_outlined,
                color: colorScheme.strokeBase,
              ),
              onTap: () async {
                _onPlatformRestrictedPaymentDetailsClick();
              },
            ),
          ),
        );
      }
    }

    widgets.add(SubFaqWidget(isOnboarding: widget.isOnboarding));

    if (!widget.isOnboarding) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: MenuItemWidgetNew(
            title: _isFreePlanUser()
                ? AppLocalizations.of(context).familyPlans
                : AppLocalizations.of(context).manageFamily,
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

    widgets.add(const SizedBox(height: 80));

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: widgets,
      ),
    );
  }

  void _onPlatformRestrictedPaymentDetailsClick() {
    final String paymentProvider = _currentSubscription!.paymentProvider;
    if (paymentProvider == appStore && !Platform.isAndroid) {
      launchUrlString("https://apps.apple.com/account/billing");
    } else if (paymentProvider == playStore && Platform.isAndroid) {
      launchUrlString(
        "https://play.google.com/store/account/subscriptions?sku=" +
            _currentSubscription!.productID +
            "&package=io.ente.photos",
      );
    } else if (paymentProvider == stripe) {
      showErrorDialog(
        context,
        AppLocalizations.of(context).sorry,
        AppLocalizations.of(context).visitWebToManage(webUrl: kPhotosWebDomain),
      );
    } else {
      final String capitalizedWord = paymentProvider.isNotEmpty
          ? '${paymentProvider[0].toUpperCase()}${paymentProvider.substring(1).toLowerCase()}'
          : '';
      showErrorDialog(
        context,
        AppLocalizations.of(context).sorry,
        AppLocalizations.of(
          context,
        ).contactToManageSubscription(provider: capitalizedWord),
      );
    }
  }

  Future<void> _filterStorePlansForUi() async {
    final billingPlans = await _billingService.getBillingPlans();
    _freePlan = billingPlans.freePlan;
    _plans = billingPlans.plans.where((plan) {
      final productID = _isActiveStripeSubscriber
          ? plan.stripeID
          : Platform.isAndroid
          ? plan.androidID
          : plan.iosID;
      return plan.id != freeProductID && productID.isNotEmpty;
    }).toList();
    hasYearlyPlans = _plans.any((plan) => plan.period == 'year');
    if (showYearlyPlan) {
      _plans = _plans.where((plan) => plan.period == 'year').toList();
    } else {
      _plans = _plans.where((plan) => plan.period != 'year').toList();
    }
    _syncOnboardingSelection();
    setState(() {});
  }

  List<Widget> _getStripePlanWidgets() {
    final List<Widget> planWidgets = [];
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
                _selectedProductID = productID;
              });
              return;
            }
            if (isActive) {
              return;
            }
            // ignore: unawaited_futures
            showErrorDialog(
              context,
              AppLocalizations.of(context).sorry,
              AppLocalizations.of(
                context,
              ).visitWebToManage(webUrl: kPhotosWebDomain),
            );
          },
          child: SubscriptionPlanWidget(
            storage: plan.storage,
            price: plan.price,
            period: plan.period,
            isActive: widget.isOnboarding
                ? _selectedProductID == productID
                : isActive && !_hideCurrentPlanSelection,
            isPopular: _isPopularPlan(plan),
            isOnboarding: widget.isOnboarding,
          ),
        ),
      );
    }
    return planWidgets;
  }

  List<Widget> _getMobilePlanWidgets() {
    final List<Widget> planWidgets = [];
    if (_shouldShowFreePlanCard()) {
      planWidgets.add(
        GestureDetector(
          onTap: () {
            if (!widget.isOnboarding) {
              return;
            }
            setState(() {
              _selectedProductID = freeProductID;
            });
          },
          child: SubscriptionPlanWidget(
            storage: _freePlan.storage,
            price: "",
            period: AppLocalizations.of(context).freeTrial,
            isActive: widget.isOnboarding
                ? _selectedProductID == freeProductID
                : _isFreePlanUser(),
            isOnboarding: widget.isOnboarding,
          ),
        ),
      );
    }
    for (final plan in _plans) {
      final productID = Platform.isAndroid ? plan.androidID : plan.iosID;
      final isActive =
          _hasActiveSubscription &&
          _currentSubscription!.productID == productID;
      planWidgets.add(
        GestureDetector(
          onTap: () async {
            if (widget.isOnboarding) {
              setState(() {
                _selectedProductID = productID;
              });
              return;
            }
            if (isActive) {
              return;
            }
            final int addOnBonus =
                _userDetails.bonusData?.totalAddOnBonus() ?? 0;
            if (_userDetails.getFamilyOrPersonalUsage() >
                (plan.storage + addOnBonus)) {
              _logger.warning(
                " familyUsage ${convertBytesToReadableFormat(_userDetails.getFamilyOrPersonalUsage())}"
                " plan storage ${convertBytesToReadableFormat(plan.storage)} "
                "addOnBonus ${convertBytesToReadableFormat(addOnBonus)},"
                "overshooting by ${convertBytesToReadableFormat(_userDetails.getFamilyOrPersonalUsage() - (plan.storage + addOnBonus))}",
              );
              // ignore: unawaited_futures
              showErrorDialog(
                context,
                AppLocalizations.of(context).sorry,
                AppLocalizations.of(context).youCannotDowngradeToThisPlan,
              );
              return;
            }
            await _dialog.show();
            final ProductDetailsResponse response = await InAppPurchase.instance
                .queryProductDetails({productID});
            if (response.notFoundIDs.isNotEmpty) {
              final errMsg =
                  "Could not find products: " + response.notFoundIDs.toString();
              _logger.severe(errMsg);
              await _dialog.hide();
              if (!mounted) return;
              await showGenericErrorDialog(
                context: context,
                error: Exception(errMsg),
              );
              return;
            }
            final isCrossGradingOnAndroid =
                Platform.isAndroid &&
                _hasActiveSubscription &&
                _currentSubscription!.productID != freeProductID &&
                _currentSubscription!.productID != plan.androidID;
            if (isCrossGradingOnAndroid) {
              await _dialog.hide();
              if (!mounted) return;
              // ignore: unawaited_futures
              showErrorDialog(
                context,
                AppLocalizations.of(context).couldNotUpdateSubscription,
                AppLocalizations.of(
                  context,
                ).pleaseContactSupportAndWeWillBeHappyToHelp,
              );
              return;
            } else {
              await InAppPurchase.instance.buyNonConsumable(
                purchaseParam: PurchaseParam(
                  productDetails: response.productDetails[0],
                ),
              );
            }
          },
          child: SubscriptionPlanWidget(
            storage: plan.storage,
            price: plan.price,
            period: plan.period,
            isActive: widget.isOnboarding
                ? _selectedProductID == productID
                : isActive,
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

  String _getPlanProductID(BillingPlan plan) {
    return _isActiveStripeSubscriber
        ? plan.stripeID
        : Platform.isAndroid
        ? plan.androidID
        : plan.iosID;
  }

  void _syncOnboardingSelection() {
    if (!widget.isOnboarding) {
      return;
    }
    final visibleProductIDs = _plans
        .map(_getPlanProductID)
        .where((id) => id.isNotEmpty)
        .toSet();
    final hasFreeOptionVisible = _shouldShowFreePlanCard();

    if (_selectedProductID == freeProductID && hasFreeOptionVisible) {
      return;
    }
    if (_selectedProductID != null &&
        visibleProductIDs.contains(_selectedProductID)) {
      return;
    }
    if (hasFreeOptionVisible) {
      _selectedProductID = freeProductID;
      return;
    }
    _selectedProductID = visibleProductIDs.isNotEmpty
        ? visibleProductIDs.first
        : null;
  }

  Future<void> _onOnboardingContinueTap() async {
    final selectedProductID = _selectedProductID;
    if (selectedProductID == null) {
      return;
    }

    if (selectedProductID == freeProductID) {
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
        .where((plan) => _getPlanProductID(plan) == selectedProductID)
        .firstOrNull;
    if (selectedPlan == null) {
      return;
    }

    if (_isActiveStripeSubscriber) {
      await showErrorDialog(
        context,
        AppLocalizations.of(context).sorry,
        AppLocalizations.of(context).visitWebToManage(webUrl: kPhotosWebDomain),
      );
      return;
    }

    final isActive =
        _hasActiveSubscription &&
        _currentSubscription!.productID == selectedProductID;
    if (isActive) {
      return;
    }

    final int addOnBonus = _userDetails.bonusData?.totalAddOnBonus() ?? 0;
    if (_userDetails.getFamilyOrPersonalUsage() >
        (selectedPlan.storage + addOnBonus)) {
      _logger.warning(
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

    await _dialog.show();
    final ProductDetailsResponse response = await InAppPurchase.instance
        .queryProductDetails({selectedProductID});
    if (response.notFoundIDs.isNotEmpty) {
      final errMsg =
          "Could not find products: " + response.notFoundIDs.toString();
      _logger.severe(errMsg);
      await _dialog.hide();
      if (!mounted) return;
      await showGenericErrorDialog(context: context, error: Exception(errMsg));
      return;
    }
    final isCrossGradingOnAndroid =
        Platform.isAndroid &&
        _hasActiveSubscription &&
        _currentSubscription!.productID != freeProductID &&
        _currentSubscription!.productID != selectedPlan.androidID;
    if (isCrossGradingOnAndroid) {
      await _dialog.hide();
      if (!mounted) return;
      await showErrorDialog(
        context,
        AppLocalizations.of(context).couldNotUpdateSubscription,
        AppLocalizations.of(context).pleaseContactSupportAndWeWillBeHappyToHelp,
      );
      return;
    }

    await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: response.productDetails[0]),
    );
  }
}
