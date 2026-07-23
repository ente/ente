// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'location_tag.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LocationTag {

 String get name; double get radius; double get aSquare; double get bSquare; Location get centerPoint;
/// Create a copy of LocationTag
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LocationTagCopyWith<LocationTag> get copyWith => _$LocationTagCopyWithImpl<LocationTag>(this as LocationTag, _$identity);

  /// Serializes this LocationTag to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LocationTag&&(identical(other.name, name) || other.name == name)&&(identical(other.radius, radius) || other.radius == radius)&&(identical(other.aSquare, aSquare) || other.aSquare == aSquare)&&(identical(other.bSquare, bSquare) || other.bSquare == bSquare)&&(identical(other.centerPoint, centerPoint) || other.centerPoint == centerPoint));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,radius,aSquare,bSquare,centerPoint);

@override
String toString() {
  return 'LocationTag(name: $name, radius: $radius, aSquare: $aSquare, bSquare: $bSquare, centerPoint: $centerPoint)';
}


}

/// @nodoc
abstract mixin class $LocationTagCopyWith<$Res>  {
  factory $LocationTagCopyWith(LocationTag value, $Res Function(LocationTag) _then) = _$LocationTagCopyWithImpl;
@useResult
$Res call({
 String name, double radius, double aSquare, double bSquare, Location centerPoint
});


$LocationCopyWith<$Res> get centerPoint;

}
/// @nodoc
class _$LocationTagCopyWithImpl<$Res>
    implements $LocationTagCopyWith<$Res> {
  _$LocationTagCopyWithImpl(this._self, this._then);

  final LocationTag _self;
  final $Res Function(LocationTag) _then;

/// Create a copy of LocationTag
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? radius = null,Object? aSquare = null,Object? bSquare = null,Object? centerPoint = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,radius: null == radius ? _self.radius : radius // ignore: cast_nullable_to_non_nullable
as double,aSquare: null == aSquare ? _self.aSquare : aSquare // ignore: cast_nullable_to_non_nullable
as double,bSquare: null == bSquare ? _self.bSquare : bSquare // ignore: cast_nullable_to_non_nullable
as double,centerPoint: null == centerPoint ? _self.centerPoint : centerPoint // ignore: cast_nullable_to_non_nullable
as Location,
  ));
}
/// Create a copy of LocationTag
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LocationCopyWith<$Res> get centerPoint {
  
  return $LocationCopyWith<$Res>(_self.centerPoint, (value) {
    return _then(_self.copyWith(centerPoint: value));
  });
}
}


/// Adds pattern-matching-related methods to [LocationTag].
extension LocationTagPatterns on LocationTag {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LocationTag value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LocationTag() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LocationTag value)  $default,){
final _that = this;
switch (_that) {
case _LocationTag():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LocationTag value)?  $default,){
final _that = this;
switch (_that) {
case _LocationTag() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  double radius,  double aSquare,  double bSquare,  Location centerPoint)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LocationTag() when $default != null:
return $default(_that.name,_that.radius,_that.aSquare,_that.bSquare,_that.centerPoint);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  double radius,  double aSquare,  double bSquare,  Location centerPoint)  $default,) {final _that = this;
switch (_that) {
case _LocationTag():
return $default(_that.name,_that.radius,_that.aSquare,_that.bSquare,_that.centerPoint);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  double radius,  double aSquare,  double bSquare,  Location centerPoint)?  $default,) {final _that = this;
switch (_that) {
case _LocationTag() when $default != null:
return $default(_that.name,_that.radius,_that.aSquare,_that.bSquare,_that.centerPoint);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LocationTag extends LocationTag {
  const _LocationTag({required this.name, required this.radius, required this.aSquare, required this.bSquare, required this.centerPoint}): super._();
  factory _LocationTag.fromJson(Map<String, dynamic> json) => _$LocationTagFromJson(json);

@override final  String name;
@override final  double radius;
@override final  double aSquare;
@override final  double bSquare;
@override final  Location centerPoint;

/// Create a copy of LocationTag
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LocationTagCopyWith<_LocationTag> get copyWith => __$LocationTagCopyWithImpl<_LocationTag>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LocationTagToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LocationTag&&(identical(other.name, name) || other.name == name)&&(identical(other.radius, radius) || other.radius == radius)&&(identical(other.aSquare, aSquare) || other.aSquare == aSquare)&&(identical(other.bSquare, bSquare) || other.bSquare == bSquare)&&(identical(other.centerPoint, centerPoint) || other.centerPoint == centerPoint));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,radius,aSquare,bSquare,centerPoint);

@override
String toString() {
  return 'LocationTag(name: $name, radius: $radius, aSquare: $aSquare, bSquare: $bSquare, centerPoint: $centerPoint)';
}


}

/// @nodoc
abstract mixin class _$LocationTagCopyWith<$Res> implements $LocationTagCopyWith<$Res> {
  factory _$LocationTagCopyWith(_LocationTag value, $Res Function(_LocationTag) _then) = __$LocationTagCopyWithImpl;
@override @useResult
$Res call({
 String name, double radius, double aSquare, double bSquare, Location centerPoint
});


@override $LocationCopyWith<$Res> get centerPoint;

}
/// @nodoc
class __$LocationTagCopyWithImpl<$Res>
    implements _$LocationTagCopyWith<$Res> {
  __$LocationTagCopyWithImpl(this._self, this._then);

  final _LocationTag _self;
  final $Res Function(_LocationTag) _then;

/// Create a copy of LocationTag
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? radius = null,Object? aSquare = null,Object? bSquare = null,Object? centerPoint = null,}) {
  return _then(_LocationTag(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,radius: null == radius ? _self.radius : radius // ignore: cast_nullable_to_non_nullable
as double,aSquare: null == aSquare ? _self.aSquare : aSquare // ignore: cast_nullable_to_non_nullable
as double,bSquare: null == bSquare ? _self.bSquare : bSquare // ignore: cast_nullable_to_non_nullable
as double,centerPoint: null == centerPoint ? _self.centerPoint : centerPoint // ignore: cast_nullable_to_non_nullable
as Location,
  ));
}

/// Create a copy of LocationTag
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LocationCopyWith<$Res> get centerPoint {
  
  return $LocationCopyWith<$Res>(_self.centerPoint, (value) {
    return _then(_self.copyWith(centerPoint: value));
  });
}
}

// dart format on
