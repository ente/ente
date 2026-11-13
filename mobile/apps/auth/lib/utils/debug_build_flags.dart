import 'package:flutter/foundation.dart';

const _skipGuidance = bool.fromEnvironment('ENTE_AUTH_SKIP_GUIDANCE');
const _allowScreenCapture = bool.fromEnvironment(
  'ENTE_AUTH_ALLOW_SCREEN_CAPTURE',
);

bool get shouldSkipAuthGuidance => kDebugMode && _skipGuidance;

bool get shouldAllowAuthScreenCapture => kDebugMode && _allowScreenCapture;
