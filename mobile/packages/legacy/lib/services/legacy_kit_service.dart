import "dart:async";

import "package:ente_configuration/base_configuration.dart";
import "package:ente_contacts/contacts.dart" as contacts;
import "package:ente_events/event_bus.dart";
import "package:ente_legacy/events/legacy_kit_created_event.dart";
import "package:ente_legacy/models/legacy_kit_models.dart";
import "package:ente_legacy/services/legacy_kit_rust_api.dart";
import "package:ente_legacy/services/legacy_kit_share_file_service.dart";
import "package:logging/logging.dart";

typedef LegacyKitSessionProvider = contacts.ContactsSession? Function();

class LegacyKitService {
  LegacyKitService._privateConstructor();

  static final LegacyKitService instance =
      LegacyKitService._privateConstructor();

  final Logger _logger = Logger("LegacyKitService");

  BaseConfiguration? _config;
  LegacyKitSessionProvider? _sessionProvider;
  LegacyKitRustApi? _rustApi;
  LegacyKitRustContext? _ctx;
  String? _ctxBaseUrl;
  int? _ctxUserId;
  String? _ctxAuthToken;

  bool get isInitialized =>
      _config != null && _sessionProvider != null && _rustApi != null;

  Future<void> init({
    required BaseConfiguration config,
    required LegacyKitSessionProvider sessionProvider,
    required LegacyKitRustApi rustApi,
  }) async {
    _config = config;
    _sessionProvider = sessionProvider;
    _rustApi = rustApi;
    unawaited(cleanStaleLegacyKitShareFiles());
  }

  Future<List<LegacyKit>> getKits() async {
    final ctx = await _requireCtx();
    return ctx.legacyKits();
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
    final createdKit = await ctx.legacyKitCreate(
      currentUserKeyAttrs: keyAttributes,
      partNames: partNames,
      noticePeriodInHours: noticePeriodInHours,
    );
    Bus.instance.fire(LegacyKitCreatedEvent());
    return createdKit;
  }

  Future<List<LegacyKitShare>> downloadShares(String kitId) async {
    final ctx = await _requireCtx();
    return ctx.legacyKitDownloadShares(kitId);
  }

  Future<LegacyKitOwnerRecoverySessionDetails> getRecoverySession(
    String kitId,
  ) async {
    final ctx = await _requireCtx();
    return ctx.legacyKitRecoverySession(kitId);
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
    await ctx.legacyKitBlockRecovery(kitId);
  }

  Future<void> deleteKit(String kitId) async {
    final ctx = await _requireCtx();
    await ctx.legacyKitDelete(kitId);
  }

  BaseConfiguration _requireConfig() {
    final config = _config;
    if (config == null) {
      throw StateError("LegacyKitService has not been initialized");
    }
    return config;
  }

  Future<LegacyKitRustContext> _requireCtx() async {
    final provider = _sessionProvider;
    final rustApi = _rustApi;
    if (provider == null || rustApi == null) {
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
        await existing.updateAuthToken(session.authToken);
        _ctxAuthToken = session.authToken;
      }
      return existing;
    }

    final accountKey = await session.resolveAccountKey();
    _logger.info("Opening legacy kit Rust context for user ${session.userId}");
    final opened = await rustApi.open(session, accountKey);
    _ctx = opened;
    _ctxBaseUrl = session.baseUrl;
    _ctxUserId = session.userId;
    _ctxAuthToken = session.authToken;
    return opened;
  }
}
