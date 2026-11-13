import 'package:ente_pure_utils/ente_pure_utils.dart';

class YearsData {
  final List<YearData> yearsData = [];
  YearsData._privateConstructor() {
    for (int year = currentYear; year >= 1970; year--) {
      yearsData.add(
        YearData(year.toString(), [
          DateTime(year).microsecondsSinceEpoch,
          DateTime(year + 1).microsecondsSinceEpoch,
        ]),
      );
    }
  }
  static final YearsData instance = YearsData._privateConstructor();
}

class YearData {
  final String year;
  final List<int> duration;
  YearData(this.year, this.duration);
}
