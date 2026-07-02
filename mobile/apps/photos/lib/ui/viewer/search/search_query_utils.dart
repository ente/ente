import "package:ente_pure_utils/ente_pure_utils.dart";

const _minimumSearchYear = 1900;

bool isYearSearchQuery(String query) {
  if (query.length != 4) {
    return false;
  }
  final yearAsInt = int.tryParse(query);
  return yearAsInt != null &&
      yearAsInt >= _minimumSearchYear &&
      yearAsInt <= currentYear;
}
