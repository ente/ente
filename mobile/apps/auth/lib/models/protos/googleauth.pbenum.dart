//
//  Generated code. Do not modify.
//  source: googleauth.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: require_trailing_commas
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class MigrationPayload_Algorithm extends $pb.ProtobufEnum {
  static const MigrationPayload_Algorithm ALGORITHM_UNSPECIFIED =
      MigrationPayload_Algorithm._(
          0, _omitEnumNames ? '' : 'ALGORITHM_UNSPECIFIED');
  static const MigrationPayload_Algorithm ALGORITHM_SHA1 =
      MigrationPayload_Algorithm._(1, _omitEnumNames ? '' : 'ALGORITHM_SHA1');
  static const MigrationPayload_Algorithm ALGORITHM_SHA256 =
      MigrationPayload_Algorithm._(2, _omitEnumNames ? '' : 'ALGORITHM_SHA256');
  static const MigrationPayload_Algorithm ALGORITHM_SHA512 =
      MigrationPayload_Algorithm._(3, _omitEnumNames ? '' : 'ALGORITHM_SHA512');
  static const MigrationPayload_Algorithm ALGORITHM_MD5 =
      MigrationPayload_Algorithm._(4, _omitEnumNames ? '' : 'ALGORITHM_MD5');

  static const $core.List<MigrationPayload_Algorithm> values =
      <MigrationPayload_Algorithm>[
    ALGORITHM_UNSPECIFIED,
    ALGORITHM_SHA1,
    ALGORITHM_SHA256,
    ALGORITHM_SHA512,
    ALGORITHM_MD5,
  ];

  static final $core.Map<$core.int, MigrationPayload_Algorithm> _byValue =
      $pb.ProtobufEnum.initByValue(values);
  static MigrationPayload_Algorithm? valueOf($core.int value) =>
      _byValue[value];

  const MigrationPayload_Algorithm._($core.int v, $core.String n) : super(v, n);
}

class MigrationPayload_DigitCount extends $pb.ProtobufEnum {
  static const MigrationPayload_DigitCount DIGIT_COUNT_UNSPECIFIED =
      MigrationPayload_DigitCount._(
          0, _omitEnumNames ? '' : 'DIGIT_COUNT_UNSPECIFIED');
  static const MigrationPayload_DigitCount DIGIT_COUNT_SIX =
      MigrationPayload_DigitCount._(1, _omitEnumNames ? '' : 'DIGIT_COUNT_SIX');
  static const MigrationPayload_DigitCount DIGIT_COUNT_EIGHT =
      MigrationPayload_DigitCount._(
          2, _omitEnumNames ? '' : 'DIGIT_COUNT_EIGHT');

  static const $core.List<MigrationPayload_DigitCount> values =
      <MigrationPayload_DigitCount>[
    DIGIT_COUNT_UNSPECIFIED,
    DIGIT_COUNT_SIX,
    DIGIT_COUNT_EIGHT,
  ];

  static final $core.Map<$core.int, MigrationPayload_DigitCount> _byValue =
      $pb.ProtobufEnum.initByValue(values);
  static MigrationPayload_DigitCount? valueOf($core.int value) =>
      _byValue[value];

  const MigrationPayload_DigitCount._($core.int v, $core.String n)
      : super(v, n);
}

class MigrationPayload_OtpType extends $pb.ProtobufEnum {
  static const MigrationPayload_OtpType OTP_TYPE_UNSPECIFIED =
      MigrationPayload_OtpType._(
          0, _omitEnumNames ? '' : 'OTP_TYPE_UNSPECIFIED');
  static const MigrationPayload_OtpType OTP_TYPE_HOTP =
      MigrationPayload_OtpType._(1, _omitEnumNames ? '' : 'OTP_TYPE_HOTP');
  static const MigrationPayload_OtpType OTP_TYPE_TOTP =
      MigrationPayload_OtpType._(2, _omitEnumNames ? '' : 'OTP_TYPE_TOTP');

  static const $core.List<MigrationPayload_OtpType> values =
      <MigrationPayload_OtpType>[
    OTP_TYPE_UNSPECIFIED,
    OTP_TYPE_HOTP,
    OTP_TYPE_TOTP,
  ];

  static final $core.Map<$core.int, MigrationPayload_OtpType> _byValue =
      $pb.ProtobufEnum.initByValue(values);
  static MigrationPayload_OtpType? valueOf($core.int value) => _byValue[value];

  const MigrationPayload_OtpType._($core.int v, $core.String n) : super(v, n);
}

const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
