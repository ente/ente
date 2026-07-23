import "dart:convert";
import "dart:math";
import "dart:typed_data";

import "package:dio/dio.dart";
import "package:ente_accounts/models/set_keys_request.dart";
import "package:ente_accounts/models/srp.dart";
import "package:ente_accounts/services/user_service.dart";
import "package:ente_base/models/key_attributes.dart";
import "package:ente_configuration/base_configuration.dart";
import "package:ente_crypto_api/ente_crypto_api.dart";
import "package:ente_legacy/models/emergency_models.dart";
import "package:ente_network/network.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_sharing/components/invite_dialog.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/alert_bottom_sheet.dart";
import "package:ente_ui/utils/dialog_util.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:pointycastle/pointycastle.dart";
import "package:pointycastle/random/fortuna_random.dart";
import "package:pointycastle/srp/srp6_client.dart";
import "package:pointycastle/srp/srp6_standard_groups.dart";
import "package:pointycastle/srp/srp6_util.dart";
import "package:pointycastle/srp/srp6_verifier_generator.dart";
import "package:uuid/uuid.dart";

class EmergencyContactService {
  final Dio _enteDio = Network.instance.enteDio;
  late UserService _userService;
  late BaseConfiguration _config;
  late final Logger _logger = Logger("EmergencyContactService");

  EmergencyContactService._privateConstructor();
  static final EmergencyContactService instance =
      EmergencyContactService._privateConstructor();

  Future<void> init(UserService userService, BaseConfiguration config) async {
    _userService = userService;
    _config = config;
  }

  Future<bool> addContact(
    BuildContext? context,
    String email,
    int recoveryNoticeInDays,
  ) async {
    if (!isValidEmail(email)) {
      if (context != null && context.mounted) {
        await showAlertBottomSheet(
          context,
          title: context.strings.letsTryThatAgain,
          message: context.strings.enterValidEmail,
          assetPath: "assets/warning-blue.png",
        );
      }
      return false;
    }
    if (email.trim() == _config.getEmail()) {
      if (context != null && context.mounted) {
        await showAlertBottomSheet(
          context,
          title: context.strings.oops,
          message: context.strings.youCannotShareWithYourself,
          assetPath: "assets/warning-blue.png",
        );
      }
      return false;
    }

    final dialog = context != null && context.mounted
        ? createProgressDialog(context, context.strings.pleaseWait)
        : null;
    await dialog?.show();

    try {
      final String? publicKey = await _userService.getPublicKey(email);
      if (publicKey == null) {
        await dialog?.hide();
        if (context != null && context.mounted) {
          await showInviteSheet(context, email: email);
        }
        return false;
      }

      final Uint8List recoveryKey = _config.getRecoveryKey();
      final encryptedKey = CryptoUtil.sealSync(
        recoveryKey,
        CryptoUtil.base642bin(publicKey),
      );
      await _enteDio.post(
        "/emergency-contacts/add",
        data: {
          "email": email.trim(),
          "encryptedKey": CryptoUtil.bin2base64(encryptedKey),
          "recoveryNoticeInDays": recoveryNoticeInDays,
        },
      );
      await dialog?.hide();
      return true;
    } catch (e) {
      await dialog?.hide();
      rethrow;
    }
  }

  Future<EmergencyInfo> getInfo() async {
    try {
      final response = await _enteDio.get("/emergency-contacts/info");
      return EmergencyInfo.fromJson(response.data);
    } catch (e, s) {
      Logger("EmergencyContact").severe('failed to get info', e, s);
      rethrow;
    }
  }

  Future<void> updateContact(
    EmergencyContact contact,
    ContactState state,
  ) async {
    try {
      await _enteDio.post(
        "/emergency-contacts/update",
        data: {
          "userID": contact.user.id,
          "emergencyContactID": contact.emergencyContact.id,
          "state": state.stringValue,
        },
      );
    } catch (e, s) {
      _logger.severe('failed to update contact', e, s);
      rethrow;
    }
  }

  Future<bool> updateRecoveryNotice(
    EmergencyContact contact,
    int recoveryNoticeInDays,
  ) async {
    try {
      await _enteDio.post(
        "/emergency-contacts/update-recovery-notice",
        data: {
          "emergencyContactID": contact.emergencyContact.id,
          "recoveryNoticeInDays": recoveryNoticeInDays,
        },
      );
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) {
        final message = e.response?.data?['message'] as String?;
        if (message != null && message.contains('active recovery session')) {
          return false;
        }
      }
      _logger.severe('failed to update recovery notice', e);
      rethrow;
    } catch (e, s) {
      _logger.severe('failed to update recovery notice', e, s);
      rethrow;
    }
  }

  Future<void> startRecovery(EmergencyContact contact) async {
    try {
      await _enteDio.post(
        "/emergency-contacts/start-recovery",
        data: {
          "userID": contact.user.id,
          "emergencyContactID": contact.emergencyContact.id,
        },
      );
    } catch (e, s) {
      Logger("EmergencyContact").severe('failed to start recovery', e, s);
      rethrow;
    }
  }

  Future<void> stopRecovery(RecoverySessions session) async {
    try {
      await _enteDio.post(
        "/emergency-contacts/stop-recovery",
        data: {
          "userID": session.user.id,
          "emergencyContactID": session.emergencyContact.id,
          "id": session.id,
        },
      );
    } catch (e, s) {
      Logger("EmergencyContact").severe('failed to stop recovery', e, s);
      rethrow;
    }
  }

  Future<void> rejectRecovery(RecoverySessions session) async {
    try {
      await _enteDio.post(
        "/emergency-contacts/reject-recovery",
        data: {
          "userID": session.user.id,
          "emergencyContactID": session.emergencyContact.id,
          "id": session.id,
        },
      );
    } catch (e, s) {
      Logger("EmergencyContact").severe('failed to stop recovery', e, s);
      rethrow;
    }
  }

  Future<void> approveRecovery(RecoverySessions session) async {
    try {
      await _enteDio.post(
        "/emergency-contacts/approve-recovery",
        data: {
          "userID": session.user.id,
          "emergencyContactID": session.emergencyContact.id,
          "id": session.id,
        },
      );
    } catch (e, s) {
      Logger("EmergencyContact").severe('failed to approve recovery', e, s);
      rethrow;
    }
  }

  Future<(String, KeyAttributes)> getRecoveryInfo(
    RecoverySessions sessions,
  ) async {
    try {
      final resp = await _enteDio.get(
        "/emergency-contacts/recovery-info/${sessions.id}",
      );
      final String encryptedKey = resp.data["encryptedKey"]!;
      final decryptedKey = CryptoUtil.openSealSync(
        CryptoUtil.base642bin(encryptedKey),
        CryptoUtil.base642bin(_config.getKeyAttributes()!.publicKey),
        _config.getSecretKey()!,
      );
      final String hexRecoveryKey = CryptoUtil.bin2hex(decryptedKey);
      final KeyAttributes keyAttributes = KeyAttributes.fromMap(
        resp.data['userKeyAttr'],
      );
      return (hexRecoveryKey, keyAttributes);
    } catch (e, s) {
      Logger("EmergencyContact").severe('failed to stop recovery', e, s);
      rethrow;
    }
  }

  Future<void> changePasswordForOther(
    Uint8List loginKey,
    SetKeysRequest setKeysRequest,
    RecoverySessions recoverySessions,
  ) async {
    try {
      final SRP6GroupParameters kDefaultSrpGroup =
          SRP6StandardGroups.rfc5054_4096;
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
        "/emergency-contacts/init-change-password",
        data: {
          "recoveryID": recoverySessions.id,
          "setupSRPRequest": request.toMap(),
        },
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
        // ignore: unused_local_variable
        late Response srpCompleteResponse;
        srpCompleteResponse = await _enteDio.post(
          "/emergency-contacts/change-password",
          data: {
            "recoveryID": recoverySessions.id,
            'updateSrpAndKeysRequest': {
              'setupID': setupSRPResponse.setupID,
              'srpM1': base64Encode(SRP6Util.encodeBigInt(clientM!)),
              'updatedKeyAttr': setKeysRequest.toMap(),
            },
          },
        );
      } else {
        throw Exception("register-srp action failed");
      }
    } catch (e, s) {
      _logger.severe("failed to change password for other", e, s);
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
}
