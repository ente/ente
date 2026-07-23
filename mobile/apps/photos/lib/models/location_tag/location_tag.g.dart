// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location_tag.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_LocationTag _$LocationTagFromJson(Map<String, dynamic> json) => _LocationTag(
  name: json['name'] as String,
  radius: (json['radius'] as num).toDouble(),
  aSquare: (json['aSquare'] as num).toDouble(),
  bSquare: (json['bSquare'] as num).toDouble(),
  centerPoint: Location.fromJson(json['centerPoint'] as Map<String, dynamic>),
);

Map<String, dynamic> _$LocationTagToJson(_LocationTag instance) =>
    <String, dynamic>{
      'name': instance.name,
      'radius': instance.radius,
      'aSquare': instance.aSquare,
      'bSquare': instance.bSquare,
      'centerPoint': instance.centerPoint,
    };
