import 'dart:async';
import "dart:io";

import 'package:dio/dio.dart';
import 'package:ente_accounts/models/errors.dart';
import 'package:ente_accounts/models/sessions.dart';
import 'package:ente_accounts/models/set_recovery_key_request.dart';
import 'package:ente_accounts/models/user_details.dart';
import 'package:ente_accounts/pages/login_page.dart';
import 'package:ente_accounts/pages/ott_verification_page.dart';
import 'package:ente_accounts/pages/passkey_page.dart';
import 'package:ente_accounts/pages/password_entry_page.dart';
import 'package:ente_accounts/pages/password_reentry_page.dart';
import 'package:ente_accounts/pages/recovery_page.dart';
import 'package:ente_accounts/pages/two_factor_authentication_page.dart';
import 'package:ente_accounts/pages/two_factor_recovery_page.dart';
import 'package:ente_accounts/services/install_source_handler.dart';
import 'package:ente_base/models/accounts.dart';
import 'package:ente_base/models/key_attributes.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_events/models/user_details_changed_event.dart';
import 'package:ente_network/network.dart';
import 'package:ente_strings/ente_strings.dart';
import "package:ente_ui/components/alert_bottom_sheet.dart";
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:ente_ui/pages/base_home_page.dart';
import 'package:ente_ui/utils/dialog_util.dart';
import 'package:ente_ui/utils/toast_util.dart';
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import "package:uuid/uuid.dart";

class UserService {
  static const keyHasEnabledTwoFactor = "has_enabled_two_factor";
  static const keyUserDetails = "user_details";
  static const kReferralSource = "referral_source";
  static const kCanDisableEmailMFA = "can_disable_email_mfa";
  static const kIsEmailMFAEnabled = "is_email_mfa_enabled";
  final _dio = Network.instance.getDio();
  final _enteDio = Network.instance.enteDio;
  final _logger = Logger((UserService).toString());
  late SharedPreferences _preferences;
  late ValueNotifier<String?> emailValueNotifier;
  late BaseConfiguration _config;
  late BaseHomePage _homePage;
  late CreateAccountsClient _createAccountsClient;
  AccountsClient? _accountsClient;
  String? _accountsClientOrigin;
  InstallSourceHandler? _installSourceHandler;

  UserService._privateConstructor();

  static final UserService instance = UserService._privateConstructor();

  Future<void> init(
    BaseConfiguration config,
    BaseHomePage homePage, {
    required CreateAccountsClient createAccountsClient,
    InstallSourceHandler? installSourceHandler,
  }) async {
    _config = config;
    _homePage = homePage;
    _createAccountsClient = createAccountsClient;
    _accountsClient = null;
    _installSourceHandler = installSourceHandler;
    emailValueNotifier = ValueNotifier<String?>(config.getEmail());
    _preferences = await SharedPreferences.getInstance();
  }

  Future<void> sendOtt(
    BuildContext? context,
    String email, {
    bool isChangeEmail = false,
    bool isCreateAccountScreen = false,
    bool isResetPasswordScreen = false,
    String? purpose,
  }) async {
    final dialog = context != null && context.mounted
        ? createProgressDialog(context, context.strings.pleaseWait)
        : null;
    await dialog?.show();
    try {
      await _withAccountsClient(
        (client) => client.sendOtp(
          email: email,
          purpose: isChangeEmail ? "change" : purpose ?? "",
          mobile: Platform.isIOS || Platform.isAndroid,
        ),
      );
      await dialog?.hide();
      if (context == null || !context.mounted) {
        return;
      }
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
      return;
    } catch (e, s) {
      await dialog?.hide();
      if (context == null || !context.mounted) return;
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
        unawaited(showGenericErrorDialog(context: context, error: e));
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
    await _dio.post(
      "${_config.getHttpEndpoint()}/anonymous/feedback",
      data: {"feedback": feedback, "type": "type"},
    );
  }

  Future<String?> getPublicKey(String email) async {
    try {
      final response = await _enteDio.get(
        "/users/public-key",
        queryParameters: {"email": email},
      );
      final publicKey = response.data["publicKey"];
      return publicKey;
    } on DioException catch (e) {
      if (e.response != null && e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<UserDetails> getUserDetailsV2({
    bool memoryCount = false,
    bool shouldCache = true,
  }) async {
    try {
      final response = await _enteDio.get(
        "/users/details/v2",
        queryParameters: {"memoryCount": memoryCount},
      );
      final userDetails = UserDetails.fromMap(response.data);
      if (shouldCache) {
        await _preferences.setString(keyUserDetails, userDetails.toJson());
        if (userDetails.profileData != null) {
          await _preferences.setBool(
            kIsEmailMFAEnabled,
            userDetails.profileData!.isEmailMFAEnabled,
          );
          await _preferences.setBool(
            kCanDisableEmailMFA,
            userDetails.profileData!.canDisableEmailMFA,
          );
        }
        if (userDetails.email != _config.getEmail()) {
          await setEmail(userDetails.email);
        }
      }
      return userDetails;
    } catch (e) {
      _logger.warning("Failed to fetch", e);
      if (e is DioException && e.response?.statusCode == 401) {
        throw UnauthorizedError();
      } else {
        rethrow;
      }
    }
  }

  UserDetails? getCachedUserDetails() {
    if (_preferences.containsKey(keyUserDetails)) {
      return UserDetails.fromJson(_preferences.getString(keyUserDetails)!);
    }
    return null;
  }

  Future<Sessions> getActiveSessions() async {
    try {
      final response = await _enteDio.get("/users/sessions");
      return Sessions.fromMap(response.data);
    } on DioException catch (e) {
      _logger.info(e);
      rethrow;
    }
  }

  Future<void> terminateSession(String token) async {
    try {
      await _enteDio.delete(
        "/users/session",
        queryParameters: {"token": token},
      );
    } on DioException catch (e) {
      _logger.info(e);
      rethrow;
    }
  }

  Future<void> leaveFamilyPlan() async {
    try {
      await _enteDio.delete("/family/leave");
    } on DioException catch (e) {
      _logger.warning('failed to leave family plan', e);
      rethrow;
    }
  }

  Future<void> logout(BuildContext context) async {
    try {
      final response = await _enteDio.post("/users/logout");
      if (response.statusCode == 200) {
        await _logoutLocally(context.mounted ? context : null);
      } else {
        throw Exception("Log out action failed");
      }
    } catch (e) {
      final bool shouldLogoutLocally =
          (e is DioException && e.response?.statusCode == 401) ||
          !_config.isEnteProduction();

      if (shouldLogoutLocally) {
        if (!_config.isEnteProduction()) {
          _logger.info(
            "Custom endpoint detected, proceeding with local logout despite server error",
          );
        } else {
          _logger.info("Token already invalid, proceeding with local logout");
        }
        await _logoutLocally(context.mounted ? context : null);
        return;
      }

      _logger.severe(e);
      // Let the logout dialog close before showing the error.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (context.mounted) {
          unawaited(showGenericErrorDialog(context: context, error: e));
        }
      });
      rethrow;
    }
  }

  Future<void> _logoutLocally(BuildContext? context) async {
    _accountsClient = null;
    await _config.logout();
    if (context == null || !context.mounted) {
      return;
    }
    unawaited(
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false),
    );
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
    BuildContext? context,
    Map response, {
    Uint8List? keyEncryptionKey,
  }) async {
    final ProgressDialog? dialog = context != null && context.mounted
        ? createProgressDialog(context, context.strings.pleaseWait)
        : null;
    await dialog?.show();
    try {
      final userPassword = _config.getVolatilePassword();
      await _saveConfiguration(response);
      if (userPassword == null) {
        await dialog?.hide();
        if (context == null || !context.mounted) {
          return;
        }
        // ignore: unawaited_futures
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext _) {
              return PasswordReentryPage(_config, _homePage);
            },
          ),
          (route) => false,
        );
        return;
      } else {
        Widget page;
        if (_config.getEncryptedToken() != null) {
          await unlockAccount(
            userPassword,
            _config.getKeyAttributes()!,
            keyEncryptionKey: keyEncryptionKey,
          );
          unawaited(autoAttributePendingSource());
          _config.resetVolatilePassword();
          page = _homePage;
        } else {
          throw Exception("unexpected response during passkey verification");
        }
        await dialog?.hide();
        if (context == null || !context.mounted) {
          return;
        }

        // ignore: unawaited_futures
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext _) {
              return page;
            },
          ),
          (route) => false,
        );
        return;
      }
    } catch (e) {
      _logger.severe(e);
      await dialog?.hide();
      rethrow;
    }
  }

  Future<void> verifyEmail(
    BuildContext context,
    String ott, {
    bool isResettingPasswordScreen = false,
  }) async {
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      final response = await _withAccountsClient(
        (client) => client.verifyEmail(
          email: _config.getEmail()!,
          code: ott,
          source: !_config.isLoggedIn()
              ? '${_config.appIdentity.referralSourcePrefix}:${_getRefSource()}'
              : null,
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
          _config,
          passkeySessionID,
          totp2FASessionID: twoFASessionID,
          accountsUrl: accountsUrl,
          redirectUrl: _config.appIdentity.passkeyRedirectUrl,
          clientPackage: _config.appIdentity.clientPackageName,
        );
      } else if (twoFASessionID.isNotEmpty) {
        page = TwoFactorAuthenticationPage(twoFASessionID);
      } else {
        await _saveConfiguration(response.toMap());
        if (_config.getEncryptedToken() != null) {
          if (isResettingPasswordScreen) {
            page = RecoveryPage(_config, _homePage);
          } else {
            page = PasswordReentryPage(_config, _homePage);
          }
        } else {
          page = PasswordEntryPage(_config, PasswordEntryMode.set, _homePage);
        }
      }
      if (!context.mounted) {
        return;
      }
      // ignore: unawaited_futures
      Navigator.of(context).pushAndRemoveUntil(
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
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      } else if (e == const AccountsError.incorrectEmailCode()) {
        // ignore: unawaited_futures
        showAlertBottomSheet(
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

  Future<void> changeEmail(
    BuildContext context,
    String email,
    String ott,
  ) async {
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      final response = await _enteDio.post(
        "/users/change-email",
        data: {"email": email, "ott": ott},
      );
      await dialog.hide();
      if (response.statusCode == 200) {
        await setEmail(email);
        Bus.instance.fire(UserDetailsChangedEvent());
        if (context.mounted) {
          showShortToast(
            context,
            context.strings.emailChangedTo(newEmail: email),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        return;
      }
      if (!context.mounted) {
        return;
      }
      // ignore: unawaited_futures
      showErrorDialog(
        context,
        context.strings.oops,
        context.strings.verificationFailedPleaseTryAgain,
      );
    } on DioException catch (e) {
      await dialog.hide();
      if (!context.mounted) {
        return;
      }
      if (e.response != null && e.response!.statusCode == 403) {
        // ignore: unawaited_futures
        showErrorDialog(
          context,
          context.strings.oops,
          context.strings.thisEmailIsAlreadyInUse,
        );
      } else {
        // ignore: unawaited_futures
        showErrorDialog(
          context,
          context.strings.incorrectCode,
          context.strings.authenticationFailedPleaseTryAgain,
        );
      }
    } catch (e) {
      await dialog.hide();
      _logger.severe(e);
      if (context.mounted) {
        // ignore: unawaited_futures
        showErrorDialog(
          context,
          context.strings.oops,
          context.strings.verificationFailedPleaseTryAgain,
        );
      }
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
    BuildContext? context,
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
    Widget page;
    final response = result.response;
    final String passkeySessionID = response.passkeySessionId ?? "";
    String twoFASessionID = response.twoFactorSessionId ?? "";
    if (twoFASessionID.isEmpty) {
      twoFASessionID = response.twoFactorSessionIdV2 ?? "";
    }
    _config.setVolatilePassword(userPassword);
    if (passkeySessionID.isNotEmpty) {
      final accountsUrl = response.accountsUrl!;
      page = PasskeyPage(
        _config,
        passkeySessionID,
        totp2FASessionID: twoFASessionID,
        accountsUrl: accountsUrl,
        keyEncryptionKey: keyEncryptionKey,
        redirectUrl: _config.appIdentity.passkeyRedirectUrl,
        clientPackage: _config.appIdentity.clientPackageName,
      );
    } else if (twoFASessionID.isNotEmpty) {
      page = TwoFactorAuthenticationPage(
        twoFASessionID,
        keyEncryptionKey: keyEncryptionKey,
      );
    } else {
      await _saveConfiguration(response.toMap());
      if (_config.getEncryptedToken() != null) {
        await unlockAccount(
          userPassword,
          _config.getKeyAttributes()!,
          keyEncryptionKey: keyEncryptionKey,
        );
        unawaited(autoAttributePendingSource());
        _config.resetVolatilePassword();
        page = _homePage;
      } else {
        throw Exception("unexpected response during email verification");
      }
    }
    await dialog.hide();
    if (context != null && context.mounted) {
      // ignore: unawaited_futures
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return page;
          },
        ),
        identical(page, _homePage)
            ? (route) => false
            : (route) => route.isFirst,
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
        keyAttributes.masterKeyEncryptedWithRecoveryKey,
        keyAttributes.masterKeyDecryptionNonce,
        keyAttributes.recoveryKeyEncryptedWithMasterKey,
        keyAttributes.recoveryKeyDecryptionNonce,
      );
      await _enteDio.put(
        "/users/recovery-key",
        data: setRecoveryKeyRequest.toMap(),
      );
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
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      final response = await _withAccountsClient(
        (client) => client.verifyTotp(sessionId: sessionID, code: code),
      );
      await dialog.hide();
      await _saveConfiguration(response.toMap());
      if (context.mounted) {
        showShortToast(context, context.strings.authenticationSuccessful);
        // ignore: unawaited_futures
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return PasswordReentryPage(
                _config,
                _homePage,
                keyEncryptionKey: keyEncryptionKey,
              );
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
        showToast(context, "Session expired");
        // ignore: unawaited_futures
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return LoginPage(_config);
            },
          ),
          (route) => route.isFirst,
        );
      } else if (e == const AccountsError.incorrectTotp()) {
        // ignore: unawaited_futures
        showAlertBottomSheet(
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
    final origin = _config.getHttpEndpoint();
    if (_accountsClient == null || _accountsClientOrigin != origin) {
      final headers = _enteDio.options.headers;
      final client = _createAccountsClient(
        config: AccountsClientConfig(
          origin: origin,
          clientPackage: headers['X-Client-Package'] as String,
          clientVersion: headers['X-Client-Version'] as String,
          userAgent: headers[HttpHeaders.userAgentHeader] as String,
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
      final client = _getAccountsClient();
      final response = await client.getTwoFactorRecovery(
        sessionId: sessionID,
        twoFactorType: type,
      );
      await dialog.hide();
      if (context.mounted) {
        // ignore: unawaited_futures
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return TwoFactorRecoveryPage(client, type, sessionID, response);
            },
          ),
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      await dialog.hide();
      _logger.severe(e);
      if (!context.mounted) {
        return;
      }
      if (e == const AccountsError.sessionExpired()) {
        showToast(context, context.strings.sessionExpired);
        // ignore: unawaited_futures
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return LoginPage(_config);
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
              return PasswordReentryPage(_config, _homePage);
            },
          ),
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      await dialog.hide();
      _logger.severe(e);
      if (!context.mounted) {
        return;
      }
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
        showToast(context, "Session expired");
        // ignore: unawaited_futures
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return LoginPage(_config);
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

  Future<void> _saveConfiguration(Map responseData) async {
    await _config.setUserID(responseData["id"]);
    if (responseData["encryptedToken"] != null) {
      await _config.setEncryptedToken(responseData["encryptedToken"]);
      await _config.setKeyAttributes(
        KeyAttributes.fromMap(responseData["keyAttributes"]),
      );
    } else {
      await _config.setToken(responseData["token"]);
    }
    final isSignUp = responseData["encryptedToken"] == null;
    unawaited(autoAttributeSource(isSignUp: isSignUp));
  }

  Future<bool> hasInstallSource() async {
    return await _installSourceHandler?.hasInstallSource() ?? false;
  }

  Future<void> autoAttributeSource({required bool isSignUp}) async {
    await _installSourceHandler?.autoAttributeSource(isSignUp: isSignUp);
  }

  Future<void> autoAttributePendingSource() async {
    await _installSourceHandler?.autoAttributePendingSource();
  }

  bool? canDisableEmailMFA() {
    return _preferences.getBool(kCanDisableEmailMFA);
  }

  bool hasEmailMFAEnabled() {
    return _preferences.getBool(kIsEmailMFAEnabled) ?? false;
  }

  Future<void> updateEmailMFA(bool isEnabled) async {
    try {
      await _enteDio.put("/users/email-mfa", data: {"isEnabled": isEnabled});
      await _preferences.setBool(kIsEmailMFAEnabled, isEnabled);
    } catch (e) {
      _logger.severe("Failed to update email mfa", e);
      rethrow;
    }
  }

  Future<void> setRefSource(String refSource) async {
    await _preferences.setString(kReferralSource, refSource);
  }

  String _getRefSource() {
    return _preferences.getString(kReferralSource) ?? "";
  }
}
