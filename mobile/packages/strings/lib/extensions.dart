import 'package:ente_strings/l10n/strings_localizations.dart';
import 'package:flutter/widgets.dart';

export 'l10n/strings_localizations.dart';

extension EnteStringsExtension on BuildContext {
  StringsLocalizations get strings => StringsLocalizations.of(this);
}
