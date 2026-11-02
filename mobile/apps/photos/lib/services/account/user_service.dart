import 'dart:async';
import "dart:io";

import 'package:dio/dio.dart';
import "package:ente_base/models/accounts.dart";
import 'package:ente_crypto/ente_crypto.dart';
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/event_bus.dart';
import "package:photos/events/account_configured_event.dart";
import 'package:photos/events/signed_in_event.dart';
import 'package:photos/events/user_details_changed_event.dart';
import 'package:photos/events/user_logged_out_event.dart';
import 'package:photos/gateways/users/models/key_attributes.dart';
import 'package:photos/gateways/users/models/sessions.dart';
import 'package:photos/gateways/users/models/set_recovery_key_request.dart';
import "package:photos/gateways/users/users_gateway.dart";
import "package:photos/models/api/collection/user.dart";
import 'package:photos/models/user_details.dart';
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import 'package:photos/src/rust/third_party/ente_frb_lib/accounts.dart'
    as accounts;
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
import 'package:shared_preferences/shared_preferences.dart';
import "package:uuid/uuid.dart";

class UserService {
  static const keyHasEnabledTwoFactor = "has_enabled_two_factor";
  static const keyUserDetails = "user_details";
  static const kReferralSource = "referral_source";
  static const kIsEmailMFAEnabled = "is_email_mfa_enabled";
  static const _publicKeyBatchSize = 10;

  final _publicKeyCache = TimedCache<String, String>(
    duration: const Duration(seconds: 10),
  );

  final _logger = Logger((UserService).toString());
  final _config = Configuration.instance;
  late SharedPreferences _preferences;
  AccountsClient? _accountsClient;
  String? _accountsClientOrigin;
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
      _accountsClient = null;
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
    bool isForgotPassword = false,
    String? purpose,
    bool isResend = false,
    VoidCallback? onChangeEmail,
  }) async {
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      await _withAccountsClient(
        (client) => client.sendOtp(
          email: email,
          purpose: isChangeEmail ? "change" : purpose ?? "",
          mobile: Platform.isIOS || Platform.isAndroid,
        ),
      );
      await dialog.hide();
      if (!context.mounted || isResend) return;
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return OTTVerificationPage(
                email,
                isChangeEmail: isChangeEmail,
                isCreateAccountScreen: isCreateAccountScreen,
                isResetPasswordScreen: isResetPasswordScreen,
                isForgotPassword: isForgotPassword,
                purpose: purpose,
                onChangeEmail: onChangeEmail,
              );
            },
          ),
        ),
      );
    } catch (e, s) {
      await dialog.hide();
      if (!context.mounted) return;
      final message = switch (e) {
        const AccountsError.alreadyRegistered() =>
          context.strings.emailAlreadyRegistered,
        const AccountsError.notRegistered() =>
          context.strings.emailNotRegistered,
        const AccountsError.signupIncomplete() =>
          context.strings.accountSetupIncompleteCreateAccount,
        const AccountsError.emailAlreadyInUse() =>
          context.strings.thisEmailIsAlreadyInUse,
        _ => null,
      };
      if (message == null) {
        _logger.warning("Failed to send OTT", e, s);
        unawaited(showGenericErrorBottomSheet(context: context, error: e));
      } else {
        _logger.info(e);
        unawaited(
          showAlertBottomSheet(
            context,
            title: context.strings.oops,
            message: message,
            assetPath: 'assets/warning-grey.png',
          ),
        );
      }
    }
  }

  Future<void> sendFeedback(
    BuildContext context,
    String feedback, {
    String type = "SubCancellation",
  }) async {
    await _gateway.sendFeedback(feedback: feedback, type: type);
  }

  Future<String?> getPublicKey(String email) async {
    email = email.trim().toLowerCase();
    final String? cachedPubKey = _publicKeyCache.get(email);
    if (cachedPubKey != null) {
      return cachedPubKey;
    }
    final publicKey = await _gateway.getPublicKey(email);
    if (publicKey != null) {
      _publicKeyCache.set(email, publicKey);
    }
    return publicKey;
  }

  Future<Map<String, String?>> getPublicKeys(Iterable<String> emails) async {
    final normalizedEmails = <String>[];
    final seen = <String>{};
    for (final email in emails) {
      final normalizedEmail = email.trim().toLowerCase();
      if (normalizedEmail.isNotEmpty && seen.add(normalizedEmail)) {
        normalizedEmails.add(normalizedEmail);
      }
    }

    final result = <String, String?>{};
    final uncached = <String>[];
    for (final email in normalizedEmails) {
      final publicKey = _publicKeyCache.get(email);
      if (publicKey == null) {
        uncached.add(email);
      } else {
        result[email] = publicKey;
      }
    }

    for (final batch in uncached.chunks(_publicKeyBatchSize)) {
      final publicKeys = await _getPublicKeyBatch(batch);
      for (var index = 0; index < batch.length; index++) {
        final publicKey = publicKeys[index];
        result[batch[index]] = publicKey;
        if (publicKey != null && publicKey.isNotEmpty) {
          _publicKeyCache.set(batch[index], publicKey);
        }
      }
    }
    return result;
  }

  Future<List<String?>> _getPublicKeyBatch(List<String> emails) async {
    try {
      return await _gateway.getPublicKeys(emails);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) {
        rethrow;
      }
    }

    final publicKeys = <String?>[];
    for (final email in emails) {
      publicKeys.add(await _gateway.getPublicKey(email));
    }
    return publicKeys;
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
      final bool silentlyIgnoreError =
          (e is DioException && e.response?.statusCode == 401) ||
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

        if (context.mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        return;
      }

      _logger.severe("Failed to logout", e);
      // Let the logout dialog close before showing the error.
      if (!context.mounted) return;
      unawaited(
        Future.delayed(const Duration(milliseconds: 150), () {
          if (!context.mounted) return;
          showGenericErrorBottomSheet(context: context, error: null);
        }),
      );
    }
  }

  Future<Map<String, dynamic>?> getTokenForPasskeySession(
    String sessionID,
  ) async {
    final response = await _withAccountsClient(
      (client) => client.pollPasskey(sessionId: sessionID),
    );
    return response?.toMap();
  }

  Future<void> onPassKeyVerified(
    BuildContext context,
    Map response, {
    Uint8List? keyEncryptionKey,
  }) async {
    final ProgressDialog dialog = createProgressDialog(
      context,
      context.strings.pleaseWait,
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
          await unlockAccount(
            userPassword,
            Configuration.instance.getKeyAttributes()!,
            keyEncryptionKey: keyEncryptionKey,
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
    bool isForgotPassword = false,
  }) async {
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      final response = await _withAccountsClient(
        (client) => client.verifyEmail(
          email: _config.getEmail()!,
          code: ott,
          source: !_config.isLoggedIn() ? _getRefSource() : null,
        ),
      );
      await dialog.hide();
      Widget page;
      final String passkeySessionID = response.passkeySessionId ?? "";
      String twoFASessionID = response.twoFactorSessionId ?? "";
      if (twoFASessionID.isEmpty) {
        twoFASessionID = response.twoFactorSessionIdV2 ?? "";
      }
      if (passkeySessionID.isNotEmpty) {
        final accountsUrl = response.accountsUrl!;
        page = PasskeyPage(
          passkeySessionID,
          totp2FASessionID: twoFASessionID,
          accountsUrl: accountsUrl,
        );
      } else if (twoFASessionID.isNotEmpty) {
        await setTwoFactor(value: true);
        page = TwoFactorAuthenticationPage(twoFASessionID);
      } else {
        await _saveConfiguration(response.toMap());
        if (Configuration.instance.getEncryptedToken() != null) {
          if (isResettingPasswordScreen) {
            page = RecoveryPage(isForgotPassword: isForgotPassword);
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
    } catch (e) {
      await dialog.hide();
      _logger.severe(e);
      if (!context.mounted) return;
      if (e == const AccountsError.emailCodeExpired()) {
        await showAlertBottomSheet(
          context,
          title: context.strings.oops,
          message: context.strings.yourVerificationCodeHasExpired,
          assetPath: 'assets/warning-grey.png',
        );
        if (!context.mounted) return;
        Navigator.of(context).pop();
      } else if (e == const AccountsError.incorrectEmailCode()) {
        await showAlertBottomSheet(
          context,
          title: context.strings.incorrectCode,
          message: context.strings.sorryTheCodeYouveEnteredIsIncorrect,
          assetPath: 'assets/warning-grey.png',
        );
      } else {
        await showAlertBottomSheet(
          context,
          title: context.strings.oops,
          message: context.strings.verificationFailedPleaseTryAgain,
          assetPath: 'assets/warning-grey.png',
        );
      }
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
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      await _gateway.changeEmail(email: email, ott: ott);
      await setEmail(email);
      await dialog.hide();
      if (context.mounted) {
        showShortToast(
          context,
          context.strings.emailChangedTo(newEmail: email),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      Bus.instance.fire(UserDetailsChangedEvent());
    } on DioException catch (e) {
      await dialog.hide();
      if (e.response != null && e.response!.statusCode == 403) {
        if (!context.mounted) return;
        await showAlertBottomSheet(
          context,
          title: context.strings.oops,
          message: context.strings.thisEmailIsAlreadyInUse,
          assetPath: 'assets/warning-grey.png',
        );
      } else {
        if (!context.mounted) return;
        await showAlertBottomSheet(
          context,
          title: context.strings.incorrectCode,
          message: context.strings.authenticationFailedPleaseTryAgain,
          assetPath: 'assets/warning-grey.png',
        );
      }
    } catch (e) {
      await dialog.hide();
      _logger.warning(e);
      if (!context.mounted) return;
      await showAlertBottomSheet(
        context,
        title: context.strings.oops,
        message: context.strings.verificationFailedPleaseTryAgain,
        assetPath: 'assets/warning-grey.png',
      );
    }
  }

  Future<SignupKeys> generateKey(String password) {
    return _withAccountsClient(
      (client) => client.generateSignupKeys(
        password: password,
        srpUserId: const Uuid().v4(),
      ),
    );
  }

  Future<void> setAttributes(SignupKeys result) async {
    await _withAccountsClient(
      (client) => client.completeSignup(
        email: _config.getEmail()!,
        token: _config.getToken()!,
        keyAttributes: result.keyAttributes,
        srp: result.srp,
      ),
    );
    await _config.setKey(result.masterKey);
    await _config.setSecretKey(result.secretKey);
    await _config.setKeyAttributes(
      KeyAttributes.fromMap(result.keyAttributes.toMap()),
    );
  }

  Future<SrpAttributes> getSrpAttributes(String email) {
    return _withAccountsClient(
      (client) => client.getSrpAttributes(email: email),
    );
  }

  Future<Uint8List> unlockAccount(
    String password,
    KeyAttributes attributes, {
    Uint8List? keyEncryptionKey,
  }) async {
    final result = await _withAccountsClient(
      (client) => client.unlock(
        response: AuthResponse(
          id: _config.getUserID()!,
          keyAttributes: accountsKeyAttributes(attributes.toMap()),
          encryptedToken: _config.getEncryptedToken(),
          token: _config.getEncryptedToken() == null
              ? _config.getToken()
              : null,
        ),
        password: password,
        keyEncryptionKey: keyEncryptionKey,
      ),
    );
    await _config.setKey(result.masterKey);
    await _config.setSecretKey(result.secretKey);
    await _config.setToken(result.token);
    return result.loginKey;
  }

  Future<void> setupSrp(Uint8List loginKey) => _withAccountsClient(
    (client) => client.setupSrp(
      token: _config.getToken()!,
      srpUserId: const Uuid().v4(),
      loginKey: loginKey,
    ),
  );

  Future<void> verifyEmailViaPassword(
    BuildContext context,
    SrpAttributes srpAttributes,
    String userPassword,
    ProgressDialog dialog,
  ) async {
    final result = await _withAccountsClient(
      (client) => client.loginWithPassword(
        attributes: srpAttributes,
        password: userPassword,
      ),
    );
    final keyEncryptionKey = result.keyEncryptionKey;
    final response = result.response;
    Widget page;
    String twoFASessionID = response.twoFactorSessionId ?? "";
    if (twoFASessionID.isEmpty) {
      twoFASessionID = response.twoFactorSessionIdV2 ?? "";
    }
    final String passkeySessionID = response.passkeySessionId ?? "";

    Configuration.instance.setVolatilePassword(userPassword);
    if (passkeySessionID.isNotEmpty) {
      final accountsUrl = response.accountsUrl!;
      page = PasskeyPage(
        passkeySessionID,
        totp2FASessionID: twoFASessionID,
        accountsUrl: accountsUrl,
        keyEncryptionKey: keyEncryptionKey,
      );
    } else if (twoFASessionID.isNotEmpty) {
      await setTwoFactor(value: true);
      page = TwoFactorAuthenticationPage(
        twoFASessionID,
        keyEncryptionKey: keyEncryptionKey,
      );
    } else {
      await _saveConfiguration(response.toMap());
      if (Configuration.instance.getEncryptedToken() != null) {
        await unlockAccount(
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

  Future<void> changePassword(
    String password, {
    required bool logoutOtherDevices,
  }) async {
    final attributes = await _withAccountsClient(
      (client) => client.changePassword(
        token: _config.getToken()!,
        password: password,
        masterKey: _config.getKey()!,
        keyAttributes: accountsKeyAttributes(
          _config.getKeyAttributes()!.toMap(),
        ),
        logOutOtherDevices: logoutOtherDevices,
      ),
    );
    await _config.setKeyAttributes(KeyAttributes.fromMap(attributes.toMap()));
  }

  Future<void> recoverAccount(String recoveryKey) async {
    final result = await _withAccountsClient(
      (client) => client.recoverAccount(
        response: AuthResponse(
          id: _config.getUserID()!,
          keyAttributes: accountsKeyAttributes(
            _config.getKeyAttributes()!.toMap(),
          ),
          encryptedToken: _config.getEncryptedToken(),
          token: _config.getEncryptedToken() == null
              ? _config.getToken()
              : null,
        ),
        recoveryKey: recoveryKey,
      ),
    );
    await _config.setKey(result.masterKey);
    await _config.setSecretKey(result.secretKey);
    await _config.setToken(result.token);
  }

  Future<String> passkeyManagementUrl() => _withAccountsClient(
    (client) => client.passkeyManagementUrl(
      token: _config.getToken()!,
      recoveryKey: CryptoUtil.bin2hex(_config.getRecoveryKey()),
    ),
  );

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
    String code, {
    Uint8List? keyEncryptionKey,
  }) async {
    final dialog = createProgressDialog(
      context,
      context.strings.authenticating,
    );
    await dialog.show();
    try {
      final response = await _withAccountsClient(
        (client) => client.verifyTotp(sessionId: sessionID, code: code),
      );
      await _saveConfiguration(response.toMap());
      await dialog.hide();
      if (context.mounted) {
        showShortToast(context, context.strings.authenticationSuccessful);
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return PasswordReentryPage(keyEncryptionKey: keyEncryptionKey);
            },
          ),
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      await dialog.hide();
      _logger.severe(e);
      if (!context.mounted) return;
      if (e == const AccountsError.sessionExpired()) {
        showToast(context, context.strings.sessionExpired);
        if (!context.mounted) return;
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return const LoginPage();
            },
          ),
          (route) => route.isFirst,
        );
      } else if (e == const AccountsError.incorrectTotp()) {
        await showAlertBottomSheet(
          context,
          title: context.strings.incorrectCode,
          message: context.strings.authenticationFailedPleaseTryAgain,
          assetPath: 'assets/warning-grey.png',
        );
      } else {
        await showAlertBottomSheet(
          context,
          title: context.strings.oops,
          message: context.strings.authenticationFailedPleaseTryAgain,
          assetPath: 'assets/warning-grey.png',
        );
      }
    }
  }

  Future<T> _withAccountsClient<T>(
    Future<T> Function(AccountsClient client) request,
  ) async {
    final client = _getAccountsClient();
    final email = _config.getEmail();
    final result = await request(client);
    if (client != _getAccountsClient() || email != _config.getEmail()) {
      throw const AccountsError.sessionExpired();
    }
    return result;
  }

  AccountsClient _getAccountsClient() {
    final origin = endpointConfig.endpoint;
    if (_accountsClient == null || _accountsClientOrigin != origin) {
      final services = ServiceLocator.instance;
      final client = accounts.createAccountsClient(
        config: AccountsClientConfig(
          origin: origin,
          clientPackage: services.packageInfo.packageName,
          clientVersion: services.packageInfo.version,
          userAgent:
              services.enteDio.options.headers[HttpHeaders.userAgentHeader]
                  as String,
        ),
      );
      _accountsClient = client;
      _accountsClientOrigin = origin;
    }
    return _accountsClient!;
  }

  Future<void> recoverTwoFactor(
    BuildContext context,
    String sessionID,
    TwoFactorType type,
  ) async {
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      _logger.info("recovering two factor");
      final client = _getAccountsClient();
      final response = await client.getTwoFactorRecovery(
        sessionId: sessionID,
        twoFactorType: type,
      );
      await dialog.hide();
      if (!context.mounted) return;
      // ignore: unawaited_futures
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return TwoFactorRecoveryPage(client, type, sessionID, response);
          },
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      await dialog.hide();
      _logger.severe('error while recovery 2fa', e);
      if (!context.mounted) return;
      if (e == const AccountsError.sessionExpired()) {
        showToast(context, context.strings.sessionExpired);
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
        // ignore: unawaited_futures
        showAlertBottomSheet(
          context,
          title: context.strings.oops,
          message: context.strings.somethingWentWrongPleaseTryAgain,
          assetPath: 'assets/warning-grey.png',
        );
      }
    } finally {
      await dialog.hide();
    }
  }

  Future<void> removeTwoFactor(
    BuildContext context,
    AccountsClient client,
    TwoFactorType type,
    String sessionID,
    String recoveryKey,
    TwoFactorRecoveryResponse recoveryResponse,
  ) async {
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      if (client != _getAccountsClient()) {
        throw const AccountsError.sessionExpired();
      }
      final response = await client.recoverTwoFactor(
        twoFactorType: type,
        sessionId: sessionID,
        recoveryResponse: recoveryResponse,
        recoveryKey: recoveryKey,
      );
      if (client != _getAccountsClient()) {
        throw const AccountsError.sessionExpired();
      }
      await _saveConfiguration(response.toMap());
      await dialog.hide();
      if (context.mounted) {
        showShortToast(
          context,
          context.strings.twofactorAuthenticationSuccessfullyReset,
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
    } catch (e) {
      await dialog.hide();
      _logger.severe("error during recovery", e);
      if (!context.mounted) return;
      if (e == const AccountsError.incorrectRecoveryKey() ||
          e == const AccountsError.malformedRecoveryKey()) {
        await showAlertBottomSheet(
          context,
          title: context.strings.incorrectRecoveryKey,
          message: e == const AccountsError.malformedRecoveryKey()
              ? context.strings.invalidRecoveryKey
              : context.strings.theRecoveryKeyYouEnteredIsIncorrect,
          assetPath: 'assets/warning-grey.png',
        );
      } else if (e == const AccountsError.sessionExpired()) {
        showToast(context, context.strings.sessionExpired);
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
        // ignore: unawaited_futures
        showAlertBottomSheet(
          context,
          title: context.strings.oops,
          message: context.strings.somethingWentWrongPleaseTryAgain,
          assetPath: 'assets/warning-grey.png',
        );
      }
    } finally {
      await dialog.hide();
    }
  }

  Future<void> setupTwoFactor(BuildContext context, Completer completer) async {
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      final responseData = await _withAccountsClient(
        (client) => client.setupTwoFactor(token: _config.getToken()!),
      );
      await dialog.hide();
      if (!context.mounted) return;
      unawaited(
        routeToPage(
          context,
          TwoFactorSetupPage(
            responseData.secretCode,
            responseData.qrCode,
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
    final dialog = createProgressDialog(context, context.strings.verifying);
    await dialog.show();
    try {
      await _withAccountsClient(
        (client) => client.enableTwoFactor(
          token: _config.getToken()!,
          secret: secret,
          recoveryKey: CryptoUtil.bin2hex(recoveryKey),
          code: code,
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
      if (e is AccountsError_IncorrectTotp) {
        if (!context.mounted) return false;
        showAlertBottomSheet(
          context,
          title: context.strings.incorrectCode,
          message: context.strings.pleaseVerifyTheCodeYouHaveEntered,
          assetPath: 'assets/warning-grey.png',
        ).ignore();
        return false;
      }
      if (!context.mounted) return false;
      // ignore: unawaited_futures
      showAlertBottomSheet(
        context,
        title: context.strings.somethingWentWrong,
        message: context.strings.pleaseContactSupportIfTheProblemPersists,
        assetPath: 'assets/warning-grey.png',
      );
    }
    return false;
  }

  Future<void> disableTwoFactor(BuildContext context) async {
    final dialog = createProgressDialog(
      context,
      context.strings.disablingTwofactorAuthentication,
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
        context.strings.twofactorAuthenticationHasBeenDisabled,
      );
    } catch (e) {
      await dialog.hide();
      _logger.severe("Failed to disabled 2FA", e);
      if (!context.mounted) return;
      await showAlertBottomSheet(
        context,
        title: context.strings.somethingWentWrong,
        message: context.strings.pleaseContactSupportIfTheProblemPersists,
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
      final dialog = createProgressDialog(context, context.strings.pleaseWait);
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

  Future<void> _saveConfiguration(Map responseData) async {
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

  List<UserSuggestion> getRelevantContacts() {
    final int ownerID = Configuration.instance.getUserID()!;
    final String ownerEmail = Configuration.instance.getEmail()!;
    final suggestions = <UserSuggestion>[];
    final existingEmails = <String>{ownerEmail};

    void add(String email, {int? userID}) {
      if (email.isNotEmpty && existingEmails.add(email)) {
        suggestions.add(UserSuggestion(email, userID: userID));
      }
    }

    for (final c in CollectionsService.instance.getActiveCollections()) {
      if (c.owner.id == ownerID) {
        for (final User u in c.sharees) {
          add(u.email, userID: u.id);
        }
      } else if (c.owner.email.isNotEmpty) {
        add(c.owner.email, userID: c.owner.id);
        final participates = c.sharees.any(
          (u) =>
              u.email == ownerEmail &&
              (u.isAdmin || u.isCollaborator || u.isViewer),
        );
        if (participates) {
          for (final User u in c.sharees) {
            if (u.isCollaborator || u.isAdmin) {
              add(u.email, userID: u.id);
            }
          }
        }
      }
    }

    final familyMembers =
        getCachedUserDetails()?.familyData?.members ?? const <FamilyMember>[];
    for (final member in familyMembers) {
      add(member.email, userID: member.userID);
    }

    for (final email in PersonService.instance.cachedLinkedPersonEmails) {
      add(email);
    }

    return suggestions;
  }
}
