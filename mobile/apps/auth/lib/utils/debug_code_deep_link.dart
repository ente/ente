import 'package:flutter/foundation.dart';

enum DebugCodeDeepLinkAction { addCode, showQr, shareCode, showIcons }

class DebugCodeDeepLink {
  const DebugCodeDeepLink({required this.action, required this.codeUri});

  final DebugCodeDeepLinkAction action;
  final String codeUri;
}

/// Parses debug-only code links used by offline UI automation.
///
/// iOS may route `otpauth://` links to the system Passwords app, even when
/// Ente Auth is installed. Wrapping the URI in Ente Auth's own scheme keeps
/// deterministic Maestro setup and visual previews out of release builds.
DebugCodeDeepLink? parseDebugCodeDeepLink(String link) {
  if (!kDebugMode) return null;

  final uri = Uri.tryParse(link);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'enteauth' ||
      uri.host.toLowerCase() != 'debug') {
    return null;
  }

  final action = switch (uri.path) {
    '/add-code' => DebugCodeDeepLinkAction.addCode,
    '/show-qr' => DebugCodeDeepLinkAction.showQr,
    '/share-code' => DebugCodeDeepLinkAction.shareCode,
    '/show-icons' => DebugCodeDeepLinkAction.showIcons,
    _ => null,
  };
  final codeUri = uri.queryParameters['uri'];
  if (action == null ||
      codeUri == null ||
      !codeUri.toLowerCase().startsWith('otpauth://')) {
    return null;
  }
  return DebugCodeDeepLink(action: action, codeUri: codeUri);
}
