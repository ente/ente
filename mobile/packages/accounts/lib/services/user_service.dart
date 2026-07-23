import 'dart:async';
import "dart:convert";
import "dart:io";
import "dart:math";

import 'package:bip39/bip39.dart' as bip39;
import 'package:dio/dio.dart';
import 'package:ente_accounts/models/errors.dart';
import 'package:ente_accounts/models/sessions.dart';
import 'package:ente_accounts/models/set_keys_request.dart';
import 'package:ente_accounts/models/set_recovery_key_request.dart';
import 'package:ente_accounts/models/srp.dart';
import 'package:ente_accounts/models/two_factor.dart';
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
import 'package:ente_base/models/key_attributes.dart';
import 'package:ente_base/models/key_gen_result.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_configuration/constants.dart';
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
  static const kCanDisableEmailMFA = "can_disable_email_mfa";
  static const kIsEmailMFAEnabled = "is_email_mfa_enabled";
  final SRP6GroupParameters kDefaultSrpGroup = SRP6StandardGroups.rfc5054_4096;
  final _dio = Network.instance.getDio();
  final _enteDio = Network.instance.enteDio;
  final _logger = Logger((UserService).toString());
  late SharedPreferences _preferences;
  late ValueNotifier<String?> emailValueNotifier;
  late BaseConfiguration _config;
  late BaseHomePage _homePage;
  InstallSourceHandler? _installSourceHandler;

  UserService._privateConstructor();

  static final UserService instance = UserService._privateConstructor();

  Future<void> init(
    BaseConfiguration config,
    BaseHomePage homePage, {
    InstallSourceHandler? installSourceHandler,
  }) async {
    _config = config;
    _homePage = homePage;
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
      final response = await _dio.post(
        "${_config.getHttpEndpoint()}/users/ott",
        data: {
          "email": email,
          "purpose": isChangeEmail ? "change" : purpose ?? "",
          "mobile": Platform.isIOS || Platform.isAndroid,
        },
      );
      await dialog?.hide();
      if (context == null || !context.mounted) {
        return;
      }
      if (response.statusCode == 200) {
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
      }
      unawaited(showGenericErrorDialog(context: context, error: null));
    } on DioException catch (e) {
      await dialog?.hide();
      _logger.info(e);
      if (context == null || !context.mounted) {
        return;
      }
      final responseData = e.response?.data;
      final Object? enteErrCode = responseData is Map
          ? responseData["code"]
          : null;
      if (enteErrCode != null && enteErrCode == "USER_ALREADY_REGISTERED") {
        unawaited(
          showAlertBottomSheet(
            context,
            title: context.strings.oops,
            message: context.strings.emailAlreadyRegistered,
            assetPath: 'assets/warning-grey.png',
          ),
        );
      } else if (enteErrCode != null && enteErrCode == "USER_NOT_REGISTERED") {
        unawaited(
          showAlertBottomSheet(
            context,
            title: context.strings.oops,
            message: context.strings.emailNotRegistered,
            assetPath: 'assets/warning-grey.png',
          ),
        );
      } else if (enteErrCode == "USER_SIGNUP_INCOMPLETE") {
        unawaited(
          showAlertBottomSheet(
            context,
            title: context.strings.oops,
            message: context.strings.accountSetupIncompleteCreateAccount,
            assetPath: 'assets/warning-grey.png',
          ),
        );
      } else if (e.response != null && e.response!.statusCode == 403) {
        unawaited(
          showAlertBottomSheet(
            context,
            title: context.strings.oops,
            message: context.strings.thisEmailIsAlreadyInUse,
            assetPath: 'assets/warning-grey.png',
          ),
        );
      } else {
        unawaited(showGenericErrorDialog(context: context, error: e));
      }
    } catch (e) {
      await dialog?.hide();
      _logger.severe(e);
      if (context != null && context.mounted) {
        unawaited(showGenericErrorDialog(context: context, error: e));
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

  // getPublicKey returns null value if email id is not
  // associated with another ente account
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
        // handle email change from different client
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
      //This future is for waiting for the dialog from which logout() is called
      //to close and only then to show the error dialog.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (context.mounted) {
          unawaited(showGenericErrorDialog(context: context, error: e));
        }
      });
      rethrow;
    }
  }

  Future<void> _logoutLocally(BuildContext? context) async {
    await _config.logout();
    if (context == null || !context.mounted) {
      return;
    }
    unawaited(
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false),
    );
  }

  Future<dynamic> getTokenForPasskeySession(String sessionID) async {
    try {
      final response = await _dio.get(
        "${_config.getHttpEndpoint()}/users/two-factor/passkeys/get-token",
        queryParameters: {"sessionID": sessionID},
      );
      return response.data;
    } on DioException catch (e) {
      if (e.response != null) {
        if (e.response!.statusCode == 404 || e.response!.statusCode == 410) {
          throw PassKeySessionExpiredError();
        }
        if (e.response!.statusCode == 400) {
          throw PassKeySessionNotVerifiedError();
        }
      }
      rethrow;
    } catch (e, s) {
      _logger.severe("unexpected error", e, s);
      rethrow;
    }
  }

  Future<void> onPassKeyVerified(BuildContext? context, Map response) async {
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
          await _config.decryptSecretsAndGetKeyEncKey(
            userPassword,
            _config.getKeyAttributes()!,
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
    final verifyData = {"email": _config.getEmail(), "ott": ott};
    if (!_config.isLoggedIn()) {
      verifyData["source"] =
          '${_config.appIdentity.referralSourcePrefix}:${_getRefSource()}';
    }
    try {
      final response = await _dio.post(
        "${_config.getHttpEndpoint()}/users/verify-email",
        data: verifyData,
      );
      await dialog.hide();
      if (response.statusCode == 200) {
        Widget page;
        final responseData = response.data;
        final String passkeySessionID = responseData["passkeySessionID"] ?? "";
        String twoFASessionID = responseData["twoFactorSessionID"] ?? "";
        if (twoFASessionID.isEmpty &&
            responseData["twoFactorSessionIDV2"] != null) {
          twoFASessionID = responseData["twoFactorSessionIDV2"];
        }
        if (passkeySessionID.isNotEmpty) {
          final accountsUrl = responseData["accountsUrl"] as String;
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
          await _saveConfiguration(response);
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
      } else {
        // should never reach here
        throw Exception("unexpected response during email verification");
      }
    } on DioException catch (e) {
      _logger.info(e);
      await dialog.hide();
      if (!context.mounted) {
        return;
      }
      if (e.response != null && e.response!.statusCode == 410) {
        await showAlertBottomSheet(
          context,
          title: context.strings.oops,
          message: context.strings.yourVerificationCodeHasExpired,
          assetPath: 'assets/warning-grey.png',
        );
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      } else {
        // ignore: unawaited_futures
        showAlertBottomSheet(
          context,
          title: context.strings.incorrectCode,
          message: context.strings.sorryTheCodeYouveEnteredIsIncorrect,
          assetPath: 'assets/warning-grey.png',
        );
      }
    } catch (e) {
      await dialog.hide();
      _logger.severe(e);
      if (context.mounted) {
        // ignore: unawaited_futures
        showAlertBottomSheet(
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
          showShortToast(context, context.strings.emailChangedTo(email));
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

  Future<void> setAttributes(KeyGenResult result) async {
    try {
      await registerOrUpdateSrp(result.loginKey);
      await _enteDio.put(
        "/users/attributes",
        data: {"keyAttributes": result.keyAttributes.toMap()},
      );
      await _config.setKey(result.privateKeyAttributes.key);
      await _config.setSecretKey(result.privateKeyAttributes.secretKey);
      await _config.setKeyAttributes(result.keyAttributes);
    } catch (e) {
      _logger.severe(e);
      rethrow;
    }
  }

  Future<SrpAttributes> getSrpAttributes(String email) async {
    try {
      final response = await _dio.get(
        "${_config.getHttpEndpoint()}/users/srp/attributes",
        queryParameters: {"email": email},
      );
      if (response.statusCode == 200) {
        return SrpAttributes.fromMap(response.data);
      } else {
        throw Exception("get-srp-attributes action failed");
      }
    } on DioException catch (e) {
      if (e.response != null && e.response!.statusCode == 404) {
        throw SrpSetupNotCompleteError();
      }
      rethrow;
    } catch (e) {
      rethrow;
    }
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
      final response = await _enteDio.post(
        "/users/srp/setup",
        data: request.toMap(),
      );
      if (response.statusCode == 200) {
        final SetupSRPResponse setupSRPResponse = SetupSRPResponse.fromJson(
          response.data,
        );
        final serverB = SRP6Util.decodeBigInt(
          base64Decode(setupSRPResponse.srpB),
        );
        // ignore: unused_local_variable
        final clientS = client.calculateSecret(serverB);
        final clientM = client.calculateClientEvidenceMessage();

        if (setKeysRequest == null) {
          await _enteDio.post(
            "/users/srp/complete",
            data: {
              'setupID': setupSRPResponse.setupID,
              'srpM1': base64Encode(SRP6Util.encodeBigInt(clientM!)),
            },
          );
        } else {
          await _enteDio.post(
            "/users/srp/update",
            data: {
              'setupID': setupSRPResponse.setupID,
              'srpM1': base64Encode(SRP6Util.encodeBigInt(clientM!)),
              'updatedKeyAttr': setKeysRequest.toMap(),
              'logOutOtherDevices': logOutOtherDevices,
            },
          );
        }
      } else {
        throw Exception("register-srp action failed");
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
    BuildContext? context,
    SrpAttributes srpAttributes,
    String userPassword,
    ProgressDialog dialog,
  ) async {
    late Uint8List keyEncryptionKey;
    _logger.finest('Start deriving key');
    keyEncryptionKey = await CryptoUtil.deriveKey(
      utf8.encode(userPassword),
      CryptoUtil.base642bin(srpAttributes.kekSalt),
      srpAttributes.memLimit,
      srpAttributes.opsLimit,
    );
    _logger.finest('keyDerivation done, derive LoginKey');
    final loginKey = await CryptoUtil.deriveLoginKey(keyEncryptionKey);
    final Uint8List identity = Uint8List.fromList(
      utf8.encode(srpAttributes.srpUserID),
    );
    _logger.finest('longinKey derivation done');
    final Uint8List salt = base64Decode(srpAttributes.srpSalt);
    final Uint8List password = loginKey;
    final SecureRandom random = _getSecureRandom();

    final client = SRP6Client(
      group: kDefaultSrpGroup,
      digest: Digest('SHA-256'),
      random: random,
    );

    final A = client.generateClientCredentials(salt, identity, password);
    final createSessionResponse = await _dio.post(
      "${_config.getHttpEndpoint()}/users/srp/create-session",
      data: {
        "srpUserID": srpAttributes.srpUserID,
        "srpA": base64Encode(SRP6Util.getPadded(A!, 512)),
      },
    );
    final String sessionID = createSessionResponse.data["sessionID"];
    final String srpB = createSessionResponse.data["srpB"];

    final serverB = SRP6Util.decodeBigInt(base64Decode(srpB));

    // ignore: unused_local_variable
    final clientS = client.calculateSecret(serverB);
    final clientM = client.calculateClientEvidenceMessage();
    final response = await _dio.post(
      "${_config.getHttpEndpoint()}/users/srp/verify-session",
      data: {
        "sessionID": sessionID,
        "srpUserID": srpAttributes.srpUserID,
        "srpM1": base64Encode(SRP6Util.getPadded(clientM!, 32)),
      },
    );
    if (response.statusCode == 200) {
      Widget? page;
      final responseData = response.data;
      final String passkeySessionID = responseData["passkeySessionID"] ?? "";
      String twoFASessionID = responseData["twoFactorSessionID"] ?? "";
      if (twoFASessionID.isEmpty &&
          responseData["twoFactorSessionIDV2"] != null) {
        twoFASessionID = responseData["twoFactorSessionIDV2"];
      }
      _config.setVolatilePassword(userPassword);
      if (passkeySessionID.isNotEmpty) {
        final accountsUrl = responseData["accountsUrl"] as String;
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
        await _saveConfiguration(response);
        if (_config.getEncryptedToken() != null) {
          await _config.decryptSecretsAndGetKeyEncKey(
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
              return page!;
            },
          ),
          identical(page, _homePage)
              ? (route) => false
              : (route) => route.isFirst,
        );
      }
    } else {
      // should never reach here
      throw Exception("unexpected response during email verification");
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
        memLimit: keyAttributes.memLimit,
        opsLimit: keyAttributes.opsLimit,
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
    String code,
  ) async {
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      final response = await _dio.post(
        "${_config.getHttpEndpoint()}/users/two-factor/verify",
        data: {"sessionID": sessionID, "code": code},
      );
      await dialog.hide();
      if (response.statusCode == 200) {
        await _saveConfiguration(response);
        if (context.mounted) {
          showShortToast(context, context.strings.authenticationSuccessful);
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
      }
    } on DioException catch (e) {
      await dialog.hide();
      _logger.severe(e);
      if (!context.mounted) {
        return;
      }
      if (e.response != null && e.response!.statusCode == 404) {
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
          title: context.strings.incorrectCode,
          message: context.strings.authenticationFailedPleaseTryAgain,
          assetPath: 'assets/warning-grey.png',
        );
      }
    } catch (e) {
      await dialog.hide();
      _logger.severe(e);
      if (context.mounted) {
        // ignore: unawaited_futures
        showAlertBottomSheet(
          context,
          title: context.strings.oops,
          message: context.strings.authenticationFailedPleaseTryAgain,
          assetPath: 'assets/warning-grey.png',
        );
      }
    }
  }

  Future<void> recoverTwoFactor(
    BuildContext context,
    String sessionID,
    TwoFactorType type,
  ) async {
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      final response = await _dio.get(
        "${_config.getHttpEndpoint()}/users/two-factor/recover",
        queryParameters: {
          "sessionID": sessionID,
          "twoFactorType": twoFactorTypeToString(type),
        },
      );
      await dialog.hide();
      if (response.statusCode == 200) {
        if (context.mounted) {
          // ignore: unawaited_futures
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (BuildContext context) {
                return TwoFactorRecoveryPage(
                  type,
                  sessionID,
                  response.data["encryptedSecret"],
                  response.data["secretDecryptionNonce"],
                );
              },
            ),
            (route) => route.isFirst,
          );
        }
      }
    } on DioException catch (e) {
      await dialog.hide();
      _logger.severe(e);
      if (!context.mounted) {
        return;
      }
      if (e.response != null && e.response!.statusCode == 404) {
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
    } catch (e) {
      await dialog.hide();
      _logger.severe(e);
      if (context.mounted) {
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
    TwoFactorType type,
    String sessionID,
    String recoveryKey,
    String encryptedSecret,
    String secretDecryptionNonce,
  ) async {
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
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
      if (!context.mounted) {
        return;
      }
      await showAlertBottomSheet(
        context,
        title: context.strings.incorrectRecoveryKey,
        message: context.strings.theRecoveryKeyYouEnteredIsIncorrect,
        assetPath: 'assets/warning-grey.png',
      );
      return;
    }
    try {
      final response = await _dio.post(
        "${_config.getHttpEndpoint()}/users/two-factor/remove",
        data: {
          "sessionID": sessionID,
          "secret": secret,
          "twoFactorType": twoFactorTypeToString(type),
        },
      );
      await dialog.hide();
      if (response.statusCode == 200) {
        await _saveConfiguration(response);
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
      }
    } on DioException catch (e) {
      await dialog.hide();
      _logger.severe(e);
      if (!context.mounted) {
        return;
      }
      if (e.response != null && e.response!.statusCode == 404) {
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
    } catch (e) {
      await dialog.hide();
      _logger.severe(e);
      if (context.mounted) {
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

  Future<void> _saveConfiguration(dynamic response) async {
    final responseData = response is Map ? response : response.data as Map?;
    if (responseData == null) return;

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
