import 'package:freezed_annotation/freezed_annotation.dart';

part 'location.freezed.dart';
part 'location.g.dart';

@freezed
abstract class Location with _$Location {
  const factory Location({
    required double? latitude,
    required double? longitude,
  }) = _Location;

  factory Location.fromJson(Map<String, Object?> json) =>
      _$LocationFromJson(json);

  static bool isValidLocation(Location? location) {
    if (location == null) return false;
    if (location.latitude == null || location.longitude == null) return false;
    final latValue = location.latitude!;
    final longValue = location.longitude!;
    if (latValue.isNaN || latValue.isInfinite) {
      return false;
    }
    if (longValue.isNaN || longValue.isInfinite) {
      return false;
    }
    if (latValue == 0.0 && longValue == 0.0) return false;
    return true;
  }

  // isValidRange checks if the latitude and longitude are within the valid range
  // for latitude and longitude. Note: We are only checking the range while
  // rending location on the map. We need to investigate in which cases we are
  // parsing incorrect location value.
  static bool isValidRange({
    required double latitude,
    required double longitude,
  }) {
    if (latitude.isNaN || latitude.isInfinite) {
      return false;
    }
    if (longitude.isNaN || longitude.isInfinite) {
      return false;
    }
    if (latitude >= 90 || latitude <= -90) {
      return false;
    }
    if (longitude >= 180 || longitude <= -180) {
      return false;
    }
    return true;
  }
}
