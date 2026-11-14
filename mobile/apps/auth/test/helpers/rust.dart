import 'dart:io';

import 'package:ente_auth/src/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

String? get rustTestSkipReason {
  final library = Platform.environment['ENTE_AUTH_FRB_LIBRARY'];
  if (library != null && library.isNotEmpty) return null;
  for (final name in ['CI', 'GITHUB_ACTIONS']) {
    final value = Platform.environment[name]?.toLowerCase();
    if (value != null && value.isNotEmpty && value != 'false' && value != '0') {
      return null;
    }
  }
  return 'Set ENTE_AUTH_FRB_LIBRARY to run Auth import tests';
}

Future<void> initializeTestRust() async {
  final library = Platform.environment['ENTE_AUTH_FRB_LIBRARY'];
  if (library == null || library.isEmpty) {
    throw StateError('Set ENTE_AUTH_FRB_LIBRARY to run Auth import tests');
  }
  await EnteAuthRust.init(externalLibrary: ExternalLibrary.open(library));
}
