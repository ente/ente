import "package:intl/intl.dart";

final _decimal = NumberFormat.decimalPattern("en_US");

String rewindCount(int value) => _decimal.format(value);

String rewindTopPercent(int perMille) =>
    perMille % 10 == 0 ? "${perMille ~/ 10}" : "${perMille / 10}";

String rewindCounted(int value, String one, String many) =>
    "${rewindCount(value)} ${value == 1 ? one : many}";
