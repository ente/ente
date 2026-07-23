import "package:fraction/fraction.dart";

enum CropValue {
  original,
  free,
  ratio_1_1,
  ratio_9_16,
  ratio_16_9,
  ratio_3_4,
  ratio_4_3;

  Fraction? getFraction() {
    switch (this) {
      case CropValue.original:
        return null;
      case CropValue.free:
        return null;
      case CropValue.ratio_1_1:
        return 1.toFraction();
      case CropValue.ratio_9_16:
        return Fraction.fromString("9/16");
      case CropValue.ratio_16_9:
        return Fraction.fromString("16/9");
      case CropValue.ratio_3_4:
        return Fraction.fromString("3/4");
      case CropValue.ratio_4_3:
        return Fraction.fromString("4/3");
    }
  }

  String get displayName {
    switch (this) {
      case CropValue.original:
        return "Original";
      case CropValue.free:
        return "Free";
      case CropValue.ratio_1_1:
        return "1:1";
      case CropValue.ratio_9_16:
        return "9:16";
      case CropValue.ratio_16_9:
        return "16:9";
      case CropValue.ratio_3_4:
        return "3:4";
      case CropValue.ratio_4_3:
        return "4:3";
    }
  }
}
