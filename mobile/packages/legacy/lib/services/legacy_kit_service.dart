import "package:ente_base/models/key_attributes.dart" as base;
import "package:ente_configuration/base_configuration.dart";
import "package:ente_contacts/contacts.dart" as contacts;
import "package:ente_events/event_bus.dart";
import "package:ente_legacy/events/legacy_kit_created_event.dart";
import "package:ente_legacy/models/legacy_kit_models.dart";
import "package:ente_rust/ente_rust.dart" as rust;
import "package:logging/logging.dart";

typedef LegacyKitSessionProvider = contacts.ContactsSession? Function();

class LegacyKitService {
  LegacyKitService._privateConstructor();

  static final LegacyKitService instance =
      LegacyKitService._privateConstructor();

  final Logger _logger = Logger("LegacyKitService");

  BaseConfiguration? _config;
  LegacyKitSessionProvider? _sessionProvider;
  rust.ContactsCtx? _ctx;
  String? _ctxBaseUrl;
  int? _ctxUserId;
  String? _ctxAuthToken;

  bool get isInitialized => _config != null && _sessionProvider != null;

  Future<void> init({
    required BaseConfiguration config,
    required LegacyKitSessionProvider sessionProvider,
  }) async {
    _config = config;
    _sessionProvider = sessionProvider;
  }

  Future<List<LegacyKit>> getKits() async {
    final ctx = await _requireCtx();
    final kits = await ctx.legacyKits();
    return kits.map(LegacyKit.fromRust).toList(growable: false);
  }

  Future<LegacyKitCreateResult> createKit({
    required List<String> partNames,
    required int noticePeriodInHours,
  }) async {
    if (partNames.length != 3) {
      throw ArgumentError.value(
        partNames,
        "partNames",
        "Legacy kit requires exactly three part names",
      );
    }
    final keyAttributes = _requireConfig().getKeyAttributes();
    if (keyAttributes == null) {
      throw StateError("Missing account key attributes");
    }
    final ctx = await _requireCtx();
    final result = await ctx.legacyKitCreate(
      currentUserKeyAttrs: _toRustKeyAttributes(keyAttributes),
      partNames: partNames,
      noticePeriodInHours: noticePeriodInHours,
    );
    final createdKit = LegacyKitCreateResult.fromRust(result);
    Bus.instance.fire(LegacyKitCreatedEvent());
    return createdKit;
  }

  Future<List<LegacyKitShare>> downloadShares(String kitId) async {
    final ctx = await _requireCtx();
    final shares = await ctx.legacyKitDownloadShares(kitId: kitId);
    return shares.map(LegacyKitShare.fromRust).toList(growable: false);
  }

  Future<LegacyKitOwnerRecoverySessionDetails> getRecoverySession(
    String kitId,
  ) async {
    final ctx = await _requireCtx();
    final details = await ctx.legacyKitRecoverySession(kitId: kitId);
    return LegacyKitOwnerRecoverySessionDetails.fromRust(details);
  }

  Future<void> updateRecoveryNotice({
    required String kitId,
    required int noticePeriodInHours,
  }) async {
    final ctx = await _requireCtx();
    await ctx.legacyKitUpdateRecoveryNotice(
      kitId: kitId,
      noticePeriodInHours: noticePeriodInHours,
    );
  }

  Future<void> blockRecovery(String kitId) async {
    final ctx = await _requireCtx();
    await ctx.legacyKitBlockRecovery(kitId: kitId);
  }

  Future<void> deleteKit(String kitId) async {
    final ctx = await _requireCtx();
    await ctx.legacyKitDelete(kitId: kitId);
  }

  BaseConfiguration _requireConfig() {
    final config = _config;
    if (config == null) {
      throw StateError("LegacyKitService has not been initialized");
    }
    return config;
  }

  Future<rust.ContactsCtx> _requireCtx() async {
    final provider = _sessionProvider;
    if (provider == null) {
      throw StateError("LegacyKitService has not been initialized");
    }
    final session = provider();
    if (session == null) {
      throw StateError("Legacy kit session is not available");
    }
    final existing = _ctx;
    if (existing != null &&
        _ctxBaseUrl == session.baseUrl &&
        _ctxUserId == session.userId) {
      if (_ctxAuthToken != session.authToken) {
        await existing.updateAuthToken(authToken: session.authToken);
        _ctxAuthToken = session.authToken;
      }
      return existing;
    }

    final accountKey = await session.resolveAccountKey();
    _logger.info("Opening legacy kit Rust context for user ${session.userId}");
    final opened = await rust.openContactsCtx(
      input: rust.OpenContactsCtxInput(
        baseUrl: session.baseUrl,
        authToken: session.authToken,
        userId: session.userId,
        masterKey: accountKey,
        userAgent: session.userAgent,
        clientPackage: session.clientPackage,
        clientVersion: session.clientVersion,
      ),
    );
    _ctx = opened.ctx;
    _ctxBaseUrl = session.baseUrl;
    _ctxUserId = session.userId;
    _ctxAuthToken = session.authToken;
    return opened.ctx;
  }

  rust.AccountKeyAttributes _toRustKeyAttributes(
    base.KeyAttributes attributes,
  ) {
    return rust.AccountKeyAttributes(
      kekSalt: attributes.kekSalt,
      encryptedKey: attributes.encryptedKey,
      keyDecryptionNonce: attributes.keyDecryptionNonce,
      publicKey: attributes.publicKey,
      encryptedSecretKey: attributes.encryptedSecretKey,
      secretKeyDecryptionNonce: attributes.secretKeyDecryptionNonce,
      memLimit: attributes.memLimit,
      opsLimit: attributes.opsLimit,
      masterKeyEncryptedWithRecoveryKey:
          attributes.masterKeyEncryptedWithRecoveryKey,
      masterKeyDecryptionNonce: attributes.masterKeyDecryptionNonce,
      recoveryKeyEncryptedWithMasterKey:
          attributes.recoveryKeyEncryptedWithMasterKey,
      recoveryKeyDecryptionNonce: attributes.recoveryKeyDecryptionNonce,
    );
  }
}
