import 'dart:async';
import "dart:convert";
import "dart:io";
import "dart:math";

import 'package:bip39/bip39.dart' as bip39;
import 'package:dio/dio.dart';
import 'package:ente_crypto/ente_crypto.dart';
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/event_bus.dart';
import "package:photos/events/account_configured_event.dart";
import 'package:photos/events/signed_in_event.dart';
import 'package:photos/events/user_details_changed_event.dart';
import 'package:photos/events/user_logged_out_event.dart';
import 'package:photos/gateways/users/models/key_attributes.dart';
import 'package:photos/gateways/users/models/key_gen_result.dart';
import 'package:photos/gateways/users/models/sessions.dart';
import 'package:photos/gateways/users/models/set_keys_request.dart';
import 'package:photos/gateways/users/models/set_recovery_key_request.dart';
import "package:photos/gateways/users/models/srp.dart";
import "package:photos/gateways/users/users_gateway.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/account/two_factor.dart";
import "package:photos/models/api/collection/user.dart";
import 'package:photos/models/user_details.dart';
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import 'package:photos/ui/account/login_page.dart';
import 'package:photos/ui/account/ott_verification_page.dart';
import "package:photos/ui/account/passkey_page.dart";
import 'package:photos/ui/account/password_entry_page.dart';
import 'package:photos/ui/account/password_reentry_page.dart';
import "package:photos/ui/account/recovery_page.dart";
import 'package:photos/ui/account/two_factor_authentication_page.dart';
import 'package:photos/ui/account/two_factor_recovery_page.dart';
import 'package:photos/ui/account/two_factor_setup_page.dart';
import "package:photos/ui/common/progress_dialog.dart";
import "package:photos/ui/components/alert_bottom_sheet.dart";
import 'package:photos/ui/notification/toast.dart';
import "package:photos/ui/tabs/home_widget.dart";
import 'package:photos/utils/dialog_util.dart';
import "package:pointycastle/export.dart";
import "package:pointycastle/srp/srp6_client.dart";
import "package:pointycastle/srp/srp6_standard_groups.dart";
import "package:pointycastle/srp/srp6_util.dart";
import "package:pointycastle/srp/srp6_verifier_generator.dart";
import 'package:shared_preferences/shared_preferences.dart';
import "package:uuid/uuid.dart";

class UserService {
  static const keyHasEnabledTwoFactor = "has_enabled_two_factor";
  static const keyUserDetails = "user_details";
  static const kReferralSource = "referral_source";
  static const kIsEmailMFAEnabled = "is_email_mfa_enabled";

  final SRP6GroupParameters kDefaultSrpGroup = SRP6StandardGroups.rfc5054_4096;
  final _emailToPubKeyCache = TimedCache<String, String>(
    duration: const Duration(seconds: 10),
  );

  final _logger = Logger((UserService).toString());
  final _config = Configuration.instance;
  late SharedPreferences _preferences;
  StreamSubscription<UserLoggedOutEvent>? _loggedOutEventSubscription;
  StreamSubscription<SignedInEvent>? _signedInEventSubscription;

  UsersGateway get _gateway => usersGateway;

  final ValueNotifier<String?> emailValueNotifier = ValueNotifier<String?>(
    null,
  );

  UserService._privateConstructor();

  static final UserService instance = UserService._privateConstructor();

  Future<void> init() async {
    emailValueNotifier.value = Configuration.instance.getEmail();
    if (_loggedOutEventSubscription != null) {
      await _loggedOutEventSubscription!.cancel();
    }
    _loggedOutEventSubscription = Bus.instance.on<UserLoggedOutEvent>().listen((
      _,
    ) {
      emailValueNotifier.value = null;
    });
    if (_signedInEventSubscription != null) {
      await _signedInEventSubscription!.cancel();
    }
    _signedInEventSubscription = Bus.instance.on<SignedInEvent>().listen((_) {
      emailValueNotifier.value = Configuration.instance.getEmail();
    });
    _preferences = await SharedPreferences.getInstance();
    if (Configuration.instance.isLoggedIn() && !isLocalGalleryMode) {
      // add artificial delay in refreshing 2FA status
      Future.delayed(
        const Duration(seconds: 5),
        () => {setTwoFactor(fetchTwoFactorStatus: true).ignore()},
      );
    }
  }

  Future<void> sendOtt(
    BuildContext context,
    String email, {
    bool isChangeEmail = false,
    bool isCreateAccountScreen = false,
    bool isResetPasswordScreen = false,
    String? purpose,
  }) async {
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).pleaseWait,
    );
    await dialog.show();
    try {
      await _gateway.sendOtt(
        email: email,
        isChangeEmail: isChangeEmail,
        purpose: purpose,
        isMobile: Platform.isIOS || Platform.isAndroid,
      );
      await dialog.hide();
      if (!context.mounted) return;
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return OTTVerificationPage(
                email,
                isChangeEmail: isChangeEmail,
                isCreateAccountScreen: isCreateAccountScreen,
                isResetPasswordScreen: isResetPasswordScreen,
              );
            },
          ),
        ),
      );
    } on DioException catch (e) {
      await dialog.hide();
      _logger.info(e);
      final responseData = e.response?.data;
      final Object? enteErrCode = responseData is Map
          ? responseData["code"]
          : null;
      if (enteErrCode != null && enteErrCode == "USER_ALREADY_REGISTERED") {
        if (!context.mounted) return;
        unawaited(
          showAlertBottomSheet(
            context,
            title: context.l10n.oops,
            message: context.l10n.emailAlreadyRegistered,
            assetPath: 'assets/warning-grey.png',
          ),
        );
      } else if (enteErrCode != null && enteErrCode == "USER_NOT_REGISTERED") {
        if (!context.mounted) return;
        unawaited(
          showAlertBottomSheet(
            context,
            title: context.l10n.oops,
            message: context.l10n.emailNotRegistered,
            assetPath: 'assets/warning-grey.png',
          ),
        );
      } else if (enteErrCode == "USER_SIGNUP_INCOMPLETE") {
        if (!context.mounted) return;
        unawaited(
          showAlertBottomSheet(
            context,
            title: context.l10n.oops,
            message: context.l10n.accountSetupIncompleteCreateAccount,
            assetPath: 'assets/warning-grey.png',
          ),
        );
      } else if (e.response != null && e.response!.statusCode == 403) {
        if (!context.mounted) return;
        unawaited(
          showAlertBottomSheet(
            context,
            title: AppLocalizations.of(context).oops,
            message: AppLocalizations.of(context).thisEmailIsAlreadyInUse,
            assetPath: 'assets/warning-grey.png',
          ),
        );
      } else {
        if (!context.mounted) return;
        unawaited(showGenericErrorBottomSheet(context: context, error: e));
      }
    } catch (e, s) {
      await dialog.hide();
      _logger.severe("Failed to send OTT", e, s);
      if (!context.mounted) return;
      unawaited(showGenericErrorBottomSheet(context: context, error: e));
    }
  }

  Future<void> sendFeedback(
    BuildContext context,
    String feedback, {
    String type = "SubCancellation",
  }) async {
    await _gateway.sendFeedback(feedback: feedback, type: type);
  }

  // getPublicKey returns null value if email id is not
  // associated with another ente account
  Future<String?> getPublicKey(String email) async {
    final String? cachedPubKey = _emailToPubKeyCache.get(email);
    if (cachedPubKey != null) {
      return cachedPubKey;
    }
    final publicKey = await _gateway.getPublicKey(email);
    if (publicKey != null) {
      _emailToPubKeyCache.set(email, publicKey);
    }
    return publicKey;
  }

  UserDetails? getCachedUserDetails() {
    if (_preferences.containsKey(keyUserDetails)) {
      return UserDetails.fromJson(_preferences.getString(keyUserDetails)!);
    }
    return null;
  }

  Future<UserDetails> getUserDetailsV2({
    bool memoryCount = true,
    bool shouldCache = true,
  }) async {
    _logger.info("Fetching user details");
    final bool previousEmailMFAStatus = hasEmailMFAEnabled();
    final bool previousTwoFactorStatus = hasEnabledTwoFactor();
    final userDetails = await _gateway.getUserDetails(memoryCount: memoryCount);
    if (shouldCache) {
      await _preferences.setString(keyUserDetails, userDetails.toJson());
      bool hasSecurityStatusChanged = false;
      if (userDetails.profileData != null) {
        final bool currentEmailMFAStatus =
            userDetails.profileData!.isEmailMFAEnabled;
        await _preferences.setBool(kIsEmailMFAEnabled, currentEmailMFAStatus);
        hasSecurityStatusChanged =
            hasSecurityStatusChanged ||
            previousEmailMFAStatus != currentEmailMFAStatus;
        final bool currentTwoFactorStatus =
            userDetails.profileData!.isTwoFactorEnabled;
        await setTwoFactor(value: currentTwoFactorStatus);
        hasSecurityStatusChanged =
            hasSecurityStatusChanged ||
            previousTwoFactorStatus != currentTwoFactorStatus;
      }
      if (hasSecurityStatusChanged) {
        Bus.instance.fire(UserDetailsChangedEvent());
      }
      // handle email change from different client
      if (userDetails.email != _config.getEmail()) {
        await setEmail(userDetails.email);
      }
    }
    return userDetails;
  }

  Future<Sessions> getActiveSessions() async {
    return _gateway.getActiveSessions();
  }

  Future<void> terminateSession(String token) async {
    await _gateway.terminateSession(token);
  }

  Future<void> leaveFamilyPlan() async {
    try {
      await _gateway.leaveFamilyPlan();
    } on DioException catch (e) {
      _logger.warning('failed to leave family plan', e);
      rethrow;
    }
  }

  Future<void> logout(BuildContext context) async {
    try {
      await _gateway.logout();
      await Configuration.instance.logout();
      if (!context.mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      // Determine if we should silently ignore the error and proceed with logout
      final bool silentlyIgnoreError =
          // Token is already invalid (401 response)
          (e is DioException && e.response?.statusCode == 401) ||
          // Custom endpoints where server might be non-existent or unavailable
          !endpointConfig.isProduction;

      if (silentlyIgnoreError) {
        if (!endpointConfig.isProduction) {
          _logger.info(
            "Custom endpoint detected, proceeding with local logout despite server error",
          );
        } else {
          _logger.info("Token already invalid, proceeding with local logout");
        }

        await Configuration.instance.logout();

        // Navigate to first route if context is still mounted
        if (context.mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        return;
      }

      _logger.severe("Failed to logout", e);
      //This future is for waiting for the dialog from which logout() is called
      //to close and only then to show the error dialog.
      if (!context.mounted) return;
      unawaited(
        Future.delayed(const Duration(milliseconds: 150), () {
          if (!context.mounted) return;
          showGenericErrorBottomSheet(context: context, error: null);
        }),
      );
    }
  }

  Future<dynamic> getTokenForPasskeySession(String sessionID) async {
    return _gateway.getTokenForPasskeySession(sessionID);
  }

  Future<void> onPassKeyVerified(BuildContext context, Map response) async {
    final ProgressDialog dialog = createProgressDialog(
      context,
      context.l10n.pleaseWait,
    );
    await dialog.show();
    try {
      final userPassword = Configuration.instance.getVolatilePassword();
      await _saveConfiguration(response);
      if (userPassword == null) {
        await dialog.hide();
        if (!context.mounted) return;
        // ignore: unawaited_futures
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return const PasswordReentryPage();
            },
          ),
          (route) => route.isFirst,
        );
      } else {
        if (Configuration.instance.getEncryptedToken() != null) {
          await Configuration.instance.decryptSecretsAndGetKeyEncKey(
            userPassword,
            Configuration.instance.getKeyAttributes()!,
          );
          unawaited(installSourceService.autoAttributePendingSource());
        } else {
          throw Exception("unexpected response during passkey verification");
        }
        await dialog.hide();
        await flagService.tryRefreshFlags();
        if (context.mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        Bus.instance.fire(AccountConfiguredEvent());
      }
    } catch (e) {
      _logger.warning(e);
      await dialog.hide();
      if (!context.mounted) return;
      await showGenericErrorBottomSheet(context: context, error: e);
    }
  }

  Future<void> verifyEmail(
    BuildContext context,
    String ott, {
    bool isResettingPasswordScreen = false,
  }) async {
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).pleaseWait,
    );
    await dialog.show();
    try {
      final responseData = await _gateway.verifyEmail(
        email: _config.getEmail()!,
        ott: ott,
        source: !_config.isLoggedIn() ? _getRefSource() : null,
      );
      await dialog.hide();
      Widget page;
      final String passkeySessionID = responseData["passkeySessionID"] ?? "";
      String twoFASessionID = responseData["twoFactorSessionID"] ?? "";
      if (twoFASessionID.isEmpty &&
          responseData["twoFactorSessionIDV2"] != null) {
        twoFASessionID = responseData["twoFactorSessionIDV2"];
      }
      if (passkeySessionID.isNotEmpty) {
        final accountsUrl = responseData["accountsUrl"] as String;
        page = PasskeyPage(
          passkeySessionID,
          totp2FASessionID: twoFASessionID,
          accountsUrl: accountsUrl,
        );
      } else if (twoFASessionID.isNotEmpty) {
        await setTwoFactor(value: true);
        page = TwoFactorAuthenticationPage(twoFASessionID);
      } else {
        await _saveConfiguration(responseData);
        if (Configuration.instance.getEncryptedToken() != null) {
          if (isResettingPasswordScreen) {
            page = const RecoveryPage();
          } else {
            page = const PasswordReentryPage();
          }
        } else {
          page = const PasswordEntryPage(mode: PasswordEntryMode.set);
        }
      }
      if (!context.mounted) return;
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return page;
          },
        ),
        (route) => route.isFirst,
      );
    } on DioException catch (e) {
      _logger.info(e);
      await dialog.hide();
      if (e.response != null && e.response!.statusCode == 410) {
        if (!context.mounted) return;
        await showAlertBottomSheet(
          context,
          title: AppLocalizations.of(context).oops,
          message: AppLocalizations.of(context).yourVerificationCodeHasExpired,
          assetPath: 'assets/warning-grey.png',
        );
        if (!context.mounted) return;
        Navigator.of(context).pop();
      } else {
        if (!context.mounted) return;
        // ignore: unawaited_futures
        showAlertBottomSheet(
          context,
          title: AppLocalizations.of(context).incorrectCode,
          message: AppLocalizations.of(
            context,
          ).sorryTheCodeYouveEnteredIsIncorrect,
          assetPath: 'assets/warning-grey.png',
        );
      }
    } catch (e) {
      await dialog.hide();
      _logger.warning(e);
      if (!context.mounted) return;
      // ignore: unawaited_futures
      showAlertBottomSheet(
        context,
        title: AppLocalizations.of(context).oops,
        message: AppLocalizations.of(context).verificationFailedPleaseTryAgain,
        assetPath: 'assets/warning-grey.png',
      );
    }
  }

  Future<void> setEmail(String email) async {
    await _config.setEmail(email);
    emailValueNotifier.value = email;
  }

  Future<void> setRefSource(String refSource) async {
    await _preferences.setString(kReferralSource, refSource);
  }

  String _getRefSource() {
    return _preferences.getString(kReferralSource) ?? "";
  }

  Future<void> changeEmail(
    BuildContext context,
    String email,
    String ott,
  ) async {
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).pleaseWait,
    );
    await dialog.show();
    try {
      await _gateway.changeEmail(email: email, ott: ott);
      await setEmail(email);
      await dialog.hide();
      if (context.mounted) {
        showShortToast(
          context,
          AppLocalizations.of(context).emailChangedTo(newEmail: email),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      Bus.instance.fire(UserDetailsChangedEvent());
    } on DioException catch (e) {
      await dialog.hide();
      if (e.response != null && e.response!.statusCode == 403) {
        if (!context.mounted) return;
        // ignore: unawaited_futures
        showAlertBottomSheet(
          context,
          title: AppLocalizations.of(context).oops,
          message: AppLocalizations.of(context).thisEmailIsAlreadyInUse,
          assetPath: 'assets/warning-grey.png',
        );
      } else {
        if (!context.mounted) return;
        // ignore: unawaited_futures
        showAlertBottomSheet(
          context,
          title: AppLocalizations.of(context).incorrectCode,
          message: AppLocalizations.of(
            context,
          ).authenticationFailedPleaseTryAgain,
          assetPath: 'assets/warning-grey.png',
        );
      }
    } catch (e) {
      await dialog.hide();
      _logger.warning(e);
      if (!context.mounted) return;
      // ignore: unawaited_futures
      showAlertBottomSheet(
        context,
        title: AppLocalizations.of(context).oops,
        message: AppLocalizations.of(context).verificationFailedPleaseTryAgain,
        assetPath: 'assets/warning-grey.png',
      );
    }
  }

  Future<void> setAttributes(KeyGenResult result) async {
    try {
      await registerOrUpdateSrp(result.loginKey);
      await _gateway.setKeyAttributes(result.keyAttributes);
      await _config.setKey(result.privateKeyAttributes.key);
      await _config.setSecretKey(result.privateKeyAttributes.secretKey);
      await _config.setKeyAttributes(result.keyAttributes);
    } catch (e) {
      _logger.severe(e);
      rethrow;
    }
  }

  Future<SrpAttributes> getSrpAttributes(String email) async {
    return _gateway.getSrpAttributes(email);
  }

  Future<void> registerOrUpdateSrp(
    Uint8List loginKey, {
    SetKeysRequest? setKeysRequest,
    bool logOutOtherDevices = false,
  }) async {
    try {
      final String username = const Uuid().v4().toString();
      final SecureRandom random = _getSecureRandom();
      final Uint8List identity = Uint8List.fromList(utf8.encode(username));
      final Uint8List password = loginKey;
      final Uint8List salt = random.nextBytes(16);
      final gen = SRP6VerifierGenerator(
        group: kDefaultSrpGroup,
        digest: Digest('SHA-256'),
      );
      final v = gen.generateVerifier(salt, identity, password);

      final client = SRP6Client(
        group: kDefaultSrpGroup,
        digest: Digest('SHA-256'),
        random: random,
      );

      final A = client.generateClientCredentials(salt, identity, password);
      final request = SetupSRPRequest(
        srpUserID: username,
        srpSalt: base64Encode(salt),
        srpVerifier: base64Encode(SRP6Util.encodeBigInt(v)),
        srpA: base64Encode(SRP6Util.encodeBigInt(A!)),
        isUpdate: false,
      );
      final setupSRPResponse = await _gateway.setupSrp(request);
      final serverB = SRP6Util.decodeBigInt(
        base64Decode(setupSRPResponse.srpB),
      );
      // ignore: unused_local_variable, need to calculate secret to get M1
      final clientS = client.calculateSecret(serverB);
      final clientM = client.calculateClientEvidenceMessage();
      if (setKeysRequest == null) {
        await _gateway.completeSrp(
          setupID: setupSRPResponse.setupID,
          srpM1: base64Encode(SRP6Util.encodeBigInt(clientM!)),
        );
      } else {
        await _gateway.updateSrp(
          setupID: setupSRPResponse.setupID,
          srpM1: base64Encode(SRP6Util.encodeBigInt(clientM!)),
          updatedKeyAttr: setKeysRequest.toMap(),
          logOutOtherDevices: logOutOtherDevices,
        );
      }
    } catch (e, s) {
      _logger.severe("failed to register srp", e, s);
      rethrow;
    }
  }

  SecureRandom _getSecureRandom() {
    final List<int> seeds = [];
    final random = Random.secure();
    for (int i = 0; i < 32; i++) {
      seeds.add(random.nextInt(255));
    }
    final secureRandom = FortunaRandom();
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  Future<void> verifyEmailViaPassword(
    BuildContext context,
    SrpAttributes srpAttributes,
    String userPassword,
    ProgressDialog dialog,
  ) async {
    late Uint8List keyEncryptionKey;
    _logger.info('Start deriving key');
    keyEncryptionKey = await CryptoUtil.deriveKey(
      utf8.encode(userPassword),
      CryptoUtil.base642bin(srpAttributes.kekSalt),
      srpAttributes.memLimit,
      srpAttributes.opsLimit,
    );
    _logger.info('keyDerivation done, derive LoginKey');
    final loginKey = await CryptoUtil.deriveLoginKey(keyEncryptionKey);
    final Uint8List identity = Uint8List.fromList(
      utf8.encode(srpAttributes.srpUserID),
    );
    _logger.info('loginKey derivation done');
    final Uint8List salt = base64Decode(srpAttributes.srpSalt);
    final Uint8List password = loginKey;
    final SecureRandom random = _getSecureRandom();

    final client = SRP6Client(
      group: kDefaultSrpGroup,
      digest: Digest('SHA-256'),
      random: random,
    );

    final A = client.generateClientCredentials(salt, identity, password);
    final createSessionResponse = await _gateway.createSrpSession(
      srpUserID: srpAttributes.srpUserID,
      srpA: base64Encode(SRP6Util.getPadded(A!, 512)),
    );
    final String sessionID = createSessionResponse["sessionID"];
    final String srpB = createSessionResponse["srpB"];

    final serverB = SRP6Util.decodeBigInt(base64Decode(srpB));
    // ignore: unused_local_variable, need to calculate secret to get M1,
    final clientS = client.calculateSecret(serverB);
    final clientM = client.calculateClientEvidenceMessage();
    final responseData = await _gateway.verifySrpSession(
      sessionID: sessionID,
      srpUserID: srpAttributes.srpUserID,
      srpM1: base64Encode(SRP6Util.getPadded(clientM!, 32)),
    );
    Widget page;
    String twoFASessionID = responseData["twoFactorSessionID"] ?? "";
    if (twoFASessionID.isEmpty &&
        responseData["twoFactorSessionIDV2"] != null) {
      twoFASessionID = responseData["twoFactorSessionIDV2"];
    }
    final String passkeySessionID = responseData["passkeySessionID"] ?? "";

    Configuration.instance.setVolatilePassword(userPassword);
    if (passkeySessionID.isNotEmpty) {
      final accountsUrl = responseData["accountsUrl"] as String;
      page = PasskeyPage(
        passkeySessionID,
        totp2FASessionID: twoFASessionID,
        accountsUrl: accountsUrl,
      );
    } else if (twoFASessionID.isNotEmpty) {
      await setTwoFactor(value: true);
      page = TwoFactorAuthenticationPage(twoFASessionID);
    } else {
      await _saveConfiguration(responseData);
      if (Configuration.instance.getEncryptedToken() != null) {
        await Configuration.instance.decryptSecretsAndGetKeyEncKey(
          userPassword,
          Configuration.instance.getKeyAttributes()!,
          keyEncryptionKey: keyEncryptionKey,
        );
        unawaited(installSourceService.autoAttributePendingSource());
        await flagService.tryRefreshFlags();
        Configuration.instance.resetVolatilePassword();
        page = const HomeWidget();
      } else {
        throw Exception("unexpected response during email verification");
      }
    }
    await dialog.hide();
    if (page is HomeWidget) {
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      Bus.instance.fire(AccountConfiguredEvent());
    } else {
      if (!context.mounted) return;
      // ignore: unawaited_futures
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return page;
          },
        ),
        (route) => route.isFirst,
      );
    }
  }

  Future<void> updateKeyAttributes(
    KeyAttributes keyAttributes,
    Uint8List loginKey, {
    required bool logoutOtherDevices,
  }) async {
    try {
      final setKeyRequest = SetKeysRequest(
        kekSalt: keyAttributes.kekSalt,
        encryptedKey: keyAttributes.encryptedKey,
        keyDecryptionNonce: keyAttributes.keyDecryptionNonce,
        memLimit: keyAttributes.memLimit!,
        opsLimit: keyAttributes.opsLimit!,
      );
      await registerOrUpdateSrp(
        loginKey,
        setKeysRequest: setKeyRequest,
        logOutOtherDevices: logoutOtherDevices,
      );
      await _config.setKeyAttributes(keyAttributes);
    } catch (e) {
      _logger.severe(e);
      rethrow;
    }
  }

  Future<void> setRecoveryKey(KeyAttributes keyAttributes) async {
    try {
      final setRecoveryKeyRequest = SetRecoveryKeyRequest(
        keyAttributes.masterKeyEncryptedWithRecoveryKey!,
        keyAttributes.masterKeyDecryptionNonce!,
        keyAttributes.recoveryKeyEncryptedWithMasterKey!,
        keyAttributes.recoveryKeyDecryptionNonce!,
      );
      await _gateway.setRecoveryKey(setRecoveryKeyRequest);
      await _config.setKeyAttributes(keyAttributes);
    } catch (e) {
      _logger.severe(e);
      rethrow;
    }
  }

  Future<void> verifyTwoFactor(
    BuildContext context,
    String sessionID,
    String code,
  ) async {
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).authenticating,
    );
    await dialog.show();
    try {
      final responseData = await _gateway.verifyTwoFactor(
        sessionID: sessionID,
        code: code,
      );
      await _saveConfiguration(responseData);
      await dialog.hide();
      if (context.mounted) {
        showShortToast(
          context,
          AppLocalizations.of(context).authenticationSuccessful,
        );
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return const PasswordReentryPage();
            },
          ),
          (route) => route.isFirst,
        );
      }
    } on DioException catch (e) {
      await dialog.hide();
      _logger.severe(e);
      if (e.response != null && e.response!.statusCode == 404) {
        if (!context.mounted) return;
        showToast(context, AppLocalizations.of(context).sessionExpired);
        if (!context.mounted) return;
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return const LoginPage();
            },
          ),
          (route) => route.isFirst,
        );
      } else {
        if (!context.mounted) return;
        // ignore: unawaited_futures
        showAlertBottomSheet(
          context,
          title: AppLocalizations.of(context).incorrectCode,
          message: AppLocalizations.of(
            context,
          ).authenticationFailedPleaseTryAgain,
          assetPath: 'assets/warning-grey.png',
        );
      }
    } catch (e) {
      await dialog.hide();
      _logger.severe(e);
      if (!context.mounted) return;
      // ignore: unawaited_futures
      showAlertBottomSheet(
        context,
        title: AppLocalizations.of(context).oops,
        message: AppLocalizations.of(
          context,
        ).authenticationFailedPleaseTryAgain,
        assetPath: 'assets/warning-grey.png',
      );
    }
  }

  Future<void> recoverTwoFactor(
    BuildContext context,
    String sessionID,
    TwoFactorType type,
  ) async {
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).pleaseWait,
    );
    await dialog.show();
    try {
      _logger.info("recovering two factor");
      final responseData = await _gateway.recoverTwoFactor(
        sessionID: sessionID,
        twoFactorType: twoFactorTypeToString(type),
      );

      await dialog.hide();
      if (!context.mounted) return;
      // ignore: unawaited_futures
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return TwoFactorRecoveryPage(
              type,
              sessionID,
              responseData["encryptedSecret"],
              responseData["secretDecryptionNonce"],
            );
          },
        ),
        (route) => route.isFirst,
      );
    } on DioException catch (e) {
      await dialog.hide();
      _logger.severe('error while recovery 2fa', e);
      if (e.response != null && e.response!.statusCode == 404) {
        if (!context.mounted) return;
        showToast(context, AppLocalizations.of(context).sessionExpired);
        if (!context.mounted) return;
        // ignore: unawaited_futures
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return const LoginPage();
            },
          ),
          (route) => route.isFirst,
        );
      } else {
        if (!context.mounted) return;
        // ignore: unawaited_futures
        showAlertBottomSheet(
          context,
          title: AppLocalizations.of(context).oops,
          message: AppLocalizations.of(
            context,
          ).somethingWentWrongPleaseTryAgain,
          assetPath: 'assets/warning-grey.png',
        );
      }
    } catch (e) {
      _logger.severe('unexpected error while recovery 2fa', e);
      await dialog.hide();
      _logger.severe(e);
      if (!context.mounted) return;
      // ignore: unawaited_futures
      showAlertBottomSheet(
        context,
        title: AppLocalizations.of(context).oops,
        message: AppLocalizations.of(context).somethingWentWrongPleaseTryAgain,
        assetPath: 'assets/warning-grey.png',
      );
    } finally {
      await dialog.hide();
    }
  }

  Future<void> removeTwoFactor(
    BuildContext context,
    TwoFactorType type,
    String sessionID,
    String recoveryKey,
    String encryptedSecret,
    String secretDecryptionNonce,
  ) async {
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).pleaseWait,
    );
    await dialog.show();
    String secret;
    try {
      if (recoveryKey.contains(' ')) {
        if (recoveryKey.split(' ').length != mnemonicKeyWordCount) {
          throw AssertionError(
            'recovery code should have $mnemonicKeyWordCount words',
          );
        }
        recoveryKey = bip39.mnemonicToEntropy(recoveryKey);
      }
      secret = CryptoUtil.bin2base64(
        await CryptoUtil.decrypt(
          CryptoUtil.base642bin(encryptedSecret),
          CryptoUtil.hex2bin(recoveryKey.trim()),
          CryptoUtil.base642bin(secretDecryptionNonce),
        ),
      );
    } catch (e) {
      await dialog.hide();
      if (!context.mounted) return;
      await showAlertBottomSheet(
        context,
        title: AppLocalizations.of(context).incorrectRecoveryKey,
        message: AppLocalizations.of(
          context,
        ).theRecoveryKeyYouEnteredIsIncorrect,
        assetPath: 'assets/warning-grey.png',
      );
      return;
    }
    try {
      final responseData = await _gateway.removeTwoFactor(
        sessionID: sessionID,
        secret: secret,
        twoFactorType: twoFactorTypeToString(type),
      );
      await _saveConfiguration(responseData);
      await dialog.hide();
      if (context.mounted) {
        showShortToast(
          context,
          AppLocalizations.of(context).twofactorAuthenticationSuccessfullyReset,
        );
        // ignore: unawaited_futures
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return const PasswordReentryPage();
            },
          ),
          (route) => route.isFirst,
        );
      }
    } on DioException catch (e) {
      await dialog.hide();
      _logger.severe("error during recovery", e);
      if (e.response != null && e.response!.statusCode == 404) {
        if (!context.mounted) return;
        showToast(context, AppLocalizations.of(context).sessionExpired);
        if (!context.mounted) return;
        // ignore: unawaited_futures
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return const LoginPage();
            },
          ),
          (route) => route.isFirst,
        );
      } else {
        if (!context.mounted) return;
        // ignore: unawaited_futures
        showAlertBottomSheet(
          context,
          title: AppLocalizations.of(context).oops,
          message: AppLocalizations.of(
            context,
          ).somethingWentWrongPleaseTryAgain,
          assetPath: 'assets/warning-grey.png',
        );
      }
    } catch (e) {
      await dialog.hide();
      _logger.severe('unexpcted error during recovery', e);

      if (!context.mounted) return;
      // ignore: unawaited_futures
      showAlertBottomSheet(
        context,
        title: AppLocalizations.of(context).oops,
        message: AppLocalizations.of(context).somethingWentWrongPleaseTryAgain,
        assetPath: 'assets/warning-grey.png',
      );
    } finally {
      await dialog.hide();
    }
  }

  Future<void> setupTwoFactor(BuildContext context, Completer completer) async {
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).pleaseWait,
    );
    await dialog.show();
    try {
      final responseData = await _gateway.setupTwoFactor();
      await dialog.hide();
      if (!context.mounted) return;
      unawaited(
        routeToPage(
          context,
          TwoFactorSetupPage(
            responseData["secretCode"],
            responseData["qrCode"],
            completer,
          ),
        ),
      );
    } catch (e) {
      await dialog.hide();
      _logger.severe("Failed to setup tfa", e);
      completer.complete();
      rethrow;
    }
  }

  Future<bool> enableTwoFactor(
    BuildContext context,
    String secret,
    String code,
  ) async {
    Uint8List recoveryKey;
    try {
      recoveryKey = await getOrCreateRecoveryKey(context);
    } catch (e) {
      if (!context.mounted) return false;
      await showGenericErrorBottomSheet(context: context, error: e);
      return false;
    }
    if (!context.mounted) return false;
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).verifying,
    );
    await dialog.show();
    final encryptionResult = CryptoUtil.encryptSync(
      CryptoUtil.base642bin(secret),
      recoveryKey,
    );
    try {
      await _gateway.enableTwoFactor(
        code: code,
        encryptedTwoFactorSecret: CryptoUtil.bin2base64(
          encryptionResult.encryptedData!,
        ),
        twoFactorSecretDecryptionNonce: CryptoUtil.bin2base64(
          encryptionResult.nonce!,
        ),
      );
      await setTwoFactor(value: true);
      await dialog.hide();
      if (context.mounted) {
        Navigator.pop(context);
      }
      Bus.instance.fire(UserDetailsChangedEvent());
      return true;
    } catch (e, s) {
      await dialog.hide();
      _logger.severe("Failed to enable 2FA", e, s);
      if (e is DioException) {
        if (e.response != null && e.response!.statusCode == 401) {
          if (!context.mounted) return false;
          // ignore: unawaited_futures
          showAlertBottomSheet(
            context,
            title: AppLocalizations.of(context).incorrectCode,
            message: AppLocalizations.of(
              context,
            ).pleaseVerifyTheCodeYouHaveEntered,
            assetPath: 'assets/warning-grey.png',
          );
          return false;
        }
      }
      if (!context.mounted) return false;
      // ignore: unawaited_futures
      showAlertBottomSheet(
        context,
        title: AppLocalizations.of(context).somethingWentWrong,
        message: AppLocalizations.of(
          context,
        ).pleaseContactSupportIfTheProblemPersists,
        assetPath: 'assets/warning-grey.png',
      );
    }
    return false;
  }

  Future<void> disableTwoFactor(BuildContext context) async {
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).disablingTwofactorAuthentication,
    );
    await dialog.show();
    try {
      await _gateway.disableTwoFactor();
      await setTwoFactor(value: false);
      await dialog.hide();
      Bus.instance.fire(UserDetailsChangedEvent());
      if (!context.mounted) return;
      showShortToast(
        context,
        AppLocalizations.of(context).twofactorAuthenticationHasBeenDisabled,
      );
    } catch (e) {
      await dialog.hide();
      _logger.severe("Failed to disabled 2FA", e);
      if (!context.mounted) return;
      await showAlertBottomSheet(
        context,
        title: AppLocalizations.of(context).somethingWentWrong,
        message: AppLocalizations.of(
          context,
        ).pleaseContactSupportIfTheProblemPersists,
        assetPath: 'assets/warning-grey.png',
      );
    }
  }

  Future<bool> fetchTwoFactorStatus() async {
    try {
      final previousStatus = hasEnabledTwoFactor();
      final status = await _gateway.getTwoFactorStatus();
      await setTwoFactor(value: status);
      if (previousStatus != status) {
        Bus.instance.fire(UserDetailsChangedEvent());
      }
      return status;
    } catch (e) {
      _logger.severe("Failed to fetch 2FA status", e);
      rethrow;
    }
  }

  Future<Uint8List> getOrCreateRecoveryKey(BuildContext context) async {
    final String? encryptedRecoveryKey = _config
        .getKeyAttributes()!
        .recoveryKeyEncryptedWithMasterKey;
    if (encryptedRecoveryKey == null || encryptedRecoveryKey.isEmpty) {
      final dialog = createProgressDialog(
        context,
        AppLocalizations.of(context).pleaseWait,
      );
      await dialog.show();
      try {
        final keyAttributes = await _config.createNewRecoveryKey();
        await setRecoveryKey(keyAttributes);
        await dialog.hide();
      } catch (e, s) {
        await dialog.hide();
        _logger.severe("Failed to create recovery key", e, s);
        rethrow;
      }
    }
    final recoveryKey = _config.getRecoveryKey();
    return recoveryKey;
  }

  Future<String?> getPaymentToken() async {
    try {
      return await _gateway.getPaymentToken();
    } catch (e) {
      _logger.severe("Failed to get payment token", e);
      return null;
    }
  }

  Future<void> _saveConfiguration(dynamic response) async {
    final responseData = response is Map ? response : response.data as Map?;
    if (responseData == null) {
      _logger.warning("(for debugging) Response data is null");
      return;
    }

    await Configuration.instance.setUserID(responseData["id"]);
    if (responseData["encryptedToken"] != null) {
      await Configuration.instance.setEncryptedToken(
        responseData["encryptedToken"],
      );
      await Configuration.instance.setKeyAttributes(
        KeyAttributes.fromMap(responseData["keyAttributes"]),
      );
    } else {
      await Configuration.instance.setToken(responseData["token"]);
    }
    final isSignUp = responseData["encryptedToken"] == null;
    unawaited(installSourceService.autoAttributeSource(isSignUp: isSignUp));

    // Initialize shared feed cutoff at login; feed path keeps the same fallback.
    localSettings.getOrCreateSharedPhotoFeedCutoffTime();
  }

  Future<void> setTwoFactor({
    bool value = false,
    bool fetchTwoFactorStatus = false,
  }) async {
    if (fetchTwoFactorStatus) {
      value = await UserService.instance.fetchTwoFactorStatus();
    }
    await _preferences.setBool(keyHasEnabledTwoFactor, value);
  }

  bool hasEnabledTwoFactor() {
    return _preferences.getBool(keyHasEnabledTwoFactor) ?? false;
  }

  bool hasEmailMFAEnabled() {
    return _preferences.getBool(kIsEmailMFAEnabled) ?? false;
  }

  Future<void> setEmailMFAStatus(bool isEnabled) async {
    await _preferences.setBool(kIsEmailMFAEnabled, isEnabled);
  }

  Future<void> updateEmailMFA(bool isEnabled) async {
    try {
      await _gateway.updateEmailMFA(isEnabled: isEnabled);

      await _preferences.setBool(kIsEmailMFAEnabled, isEnabled);

      final UserDetails? profile = getCachedUserDetails();
      if (profile != null && profile.profileData != null) {
        profile.profileData!.isEmailMFAEnabled = isEnabled;
        await _preferences.setString(keyUserDetails, profile.toJson());
      }
      Bus.instance.fire(UserDetailsChangedEvent());
    } catch (e) {
      _logger.severe("Failed to update email mfa", e);
      rethrow;
    }
  }

  /// Returns Contacts(Users) that are relevant to the account owner.
  /// Note: "User" refers to the account owner in the points below.
  /// This includes:
  /// 	- Collaborators and viewers of collections owned by user
  ///   - Owners of collections shared to user.
  ///   - All collaborators of collections in which user is a collaborator or
  ///     a viewer.
  ///   - All family members of user.
  ///   - All contacts linked to a person.
  List<User> getRelevantContacts() {
    final List<User> relevantUsers = [];
    final existingEmails = <String>{};
    final int ownerID = Configuration.instance.getUserID()!;
    final String ownerEmail = Configuration.instance.getEmail()!;
    existingEmails.add(ownerEmail);

    for (final c in CollectionsService.instance.getActiveCollections()) {
      // Add collaborators and viewers of collections owned by user
      if (c.owner.id == ownerID) {
        for (final User u in c.sharees) {
          if (u.id != null && u.email.isNotEmpty) {
            if (!existingEmails.contains(u.email)) {
              relevantUsers.add(u);
              existingEmails.add(u.email);
            }
          }
        }
      } else if (c.owner.id != null && c.owner.email.isNotEmpty) {
        // Add owners of collections shared with user
        if (!existingEmails.contains(c.owner.email)) {
          relevantUsers.add(c.owner);
          existingEmails.add(c.owner.email);
        }
        // Add collaborators of collections shared with user where user is a
        // viewer or a collaborator
        for (final User u in c.sharees) {
          if (u.id != null &&
              u.email.isNotEmpty &&
              u.email == ownerEmail &&
              (u.isAdmin || u.isCollaborator || u.isViewer)) {
            for (final User u in c.sharees) {
              if (u.id != null &&
                  u.email.isNotEmpty &&
                  (u.isCollaborator || u.isAdmin)) {
                if (!existingEmails.contains(u.email)) {
                  relevantUsers.add(u);
                  existingEmails.add(u.email);
                }
              }
            }
            break;
          }
        }
      }
    }

    // Add user's family members
    final cachedUserDetails = getCachedUserDetails();
    if (cachedUserDetails?.familyData?.members?.isNotEmpty ?? false) {
      for (final member in cachedUserDetails!.familyData!.members!) {
        if (!existingEmails.contains(member.email)) {
          relevantUsers.add(User(email: member.email));
          existingEmails.add(member.email);
        }
      }
    }

    // Add contacts linked to people
    final cachedEmailToPartialPersonData =
        PersonService.instance.emailToPartialPersonDataMapCache;
    for (final email in cachedEmailToPartialPersonData.keys) {
      if (!existingEmails.contains(email)) {
        relevantUsers.add(User(email: email));
        existingEmails.add(email);
      }
    }

    return relevantUsers;
  }

  /// Returns emails of Users that are relevant to the account owner.
  /// Note: "User" refers to the account owner in the points below.
  /// This includes:
  /// 	- Collaborators and viewers of collections owned by user
  ///   - Owners of collections shared to user.
  ///   - All collaborators of collections in which user is a collaborator or
  ///     a viewer.
  ///   - All family members of user.
  ///   - All contacts linked to a person.
  Set<String> getEmailIDsOfRelevantContacts() {
    final emailIDs = <String>{};

    final int ownerID = Configuration.instance.getUserID()!;
    final String ownerEmail = Configuration.instance.getEmail()!;

    for (final c in CollectionsService.instance.getActiveCollections()) {
      // Add collaborators and viewers of collections owned by user
      if (c.owner.id == ownerID) {
        for (final User u in c.sharees) {
          if (u.id != null && u.email.isNotEmpty) {
            if (!emailIDs.contains(u.email)) {
              emailIDs.add(u.email);
            }
          }
        }
      } else if (c.owner.id != null && c.owner.email.isNotEmpty) {
        // Add owners of collections shared with user
        if (!emailIDs.contains(c.owner.email)) {
          emailIDs.add(c.owner.email);
        }
        // Add collaborators of collections shared with user where user is a
        // viewer or a collaborator
        for (final User u in c.sharees) {
          if (u.id != null &&
              u.email.isNotEmpty &&
              u.email == ownerEmail &&
              (u.isAdmin || u.isCollaborator || u.isViewer)) {
            for (final User u in c.sharees) {
              if (u.id != null &&
                  u.email.isNotEmpty &&
                  (u.isCollaborator || u.isAdmin)) {
                if (!emailIDs.contains(u.email)) {
                  emailIDs.add(u.email);
                }
              }
            }
            break;
          }
        }
      }
    }

    // Add user's family members
    final cachedUserDetails = getCachedUserDetails();
    if (cachedUserDetails?.familyData?.members?.isNotEmpty ?? false) {
      for (final member in cachedUserDetails!.familyData!.members!) {
        if (!emailIDs.contains(member.email)) {
          emailIDs.add(member.email);
        }
      }
    }

    // Add contacts linked to people
    final cachedEmailToPartialPersonData =
        PersonService.instance.emailToPartialPersonDataMapCache;
    for (final email in cachedEmailToPartialPersonData.keys) {
      if (!emailIDs.contains(email)) {
        emailIDs.add(email);
      }
    }

    emailIDs.remove(ownerEmail);

    return emailIDs;
  }

  Set<String> getEmailIDsOfFamilyMember() {
    final emailIDs = <String>{};

    final cachedUserDetails = getCachedUserDetails();
    if (cachedUserDetails?.familyData?.members?.isNotEmpty ?? false) {
      for (final member in cachedUserDetails!.familyData!.members!) {
        if (member.email.isNotEmpty) {
          emailIDs.add(member.email);
        }
      }
    }

    return emailIDs;
  }
}
