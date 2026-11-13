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

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use migrationPayloadDescriptor instead')
const MigrationPayload$json = {
  '1': 'MigrationPayload',
  '2': [
    {
      '1': 'otp_parameters',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.googleauth.MigrationPayload.OtpParameters',
      '10': 'otpParameters'
    },
    {'1': 'version', '3': 2, '4': 1, '5': 5, '10': 'version'},
    {'1': 'batch_size', '3': 3, '4': 1, '5': 5, '10': 'batchSize'},
    {'1': 'batch_index', '3': 4, '4': 1, '5': 5, '10': 'batchIndex'},
    {'1': 'batch_id', '3': 5, '4': 1, '5': 5, '10': 'batchId'},
  ],
  '3': [MigrationPayload_OtpParameters$json],
  '4': [
    MigrationPayload_Algorithm$json,
    MigrationPayload_DigitCount$json,
    MigrationPayload_OtpType$json
  ],
};

@$core.Deprecated('Use migrationPayloadDescriptor instead')
const MigrationPayload_OtpParameters$json = {
  '1': 'OtpParameters',
  '2': [
    {'1': 'secret', '3': 1, '4': 1, '5': 12, '10': 'secret'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'issuer', '3': 3, '4': 1, '5': 9, '10': 'issuer'},
    {
      '1': 'algorithm',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.googleauth.MigrationPayload.Algorithm',
      '10': 'algorithm'
    },
    {
      '1': 'digits',
      '3': 5,
      '4': 1,
      '5': 14,
      '6': '.googleauth.MigrationPayload.DigitCount',
      '10': 'digits'
    },
    {
      '1': 'type',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.googleauth.MigrationPayload.OtpType',
      '10': 'type'
    },
    {'1': 'counter', '3': 7, '4': 1, '5': 3, '10': 'counter'},
  ],
};

@$core.Deprecated('Use migrationPayloadDescriptor instead')
const MigrationPayload_Algorithm$json = {
  '1': 'Algorithm',
  '2': [
    {'1': 'ALGORITHM_UNSPECIFIED', '2': 0},
    {'1': 'ALGORITHM_SHA1', '2': 1},
    {'1': 'ALGORITHM_SHA256', '2': 2},
    {'1': 'ALGORITHM_SHA512', '2': 3},
    {'1': 'ALGORITHM_MD5', '2': 4},
  ],
};

@$core.Deprecated('Use migrationPayloadDescriptor instead')
const MigrationPayload_DigitCount$json = {
  '1': 'DigitCount',
  '2': [
    {'1': 'DIGIT_COUNT_UNSPECIFIED', '2': 0},
    {'1': 'DIGIT_COUNT_SIX', '2': 1},
    {'1': 'DIGIT_COUNT_EIGHT', '2': 2},
  ],
};

@$core.Deprecated('Use migrationPayloadDescriptor instead')
const MigrationPayload_OtpType$json = {
  '1': 'OtpType',
  '2': [
    {'1': 'OTP_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'OTP_TYPE_HOTP', '2': 1},
    {'1': 'OTP_TYPE_TOTP', '2': 2},
  ],
};

/// Descriptor for `MigrationPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List migrationPayloadDescriptor = $convert.base64Decode(
    'ChBNaWdyYXRpb25QYXlsb2FkElEKDm90cF9wYXJhbWV0ZXJzGAEgAygLMiouZ29vZ2xlYXV0aC'
    '5NaWdyYXRpb25QYXlsb2FkLk90cFBhcmFtZXRlcnNSDW90cFBhcmFtZXRlcnMSGAoHdmVyc2lv'
    'bhgCIAEoBVIHdmVyc2lvbhIdCgpiYXRjaF9zaXplGAMgASgFUgliYXRjaFNpemUSHwoLYmF0Y2'
    'hfaW5kZXgYBCABKAVSCmJhdGNoSW5kZXgSGQoIYmF0Y2hfaWQYBSABKAVSB2JhdGNoSWQargIK'
    'DU90cFBhcmFtZXRlcnMSFgoGc2VjcmV0GAEgASgMUgZzZWNyZXQSEgoEbmFtZRgCIAEoCVIEbm'
    'FtZRIWCgZpc3N1ZXIYAyABKAlSBmlzc3VlchJECglhbGdvcml0aG0YBCABKA4yJi5nb29nbGVh'
    'dXRoLk1pZ3JhdGlvblBheWxvYWQuQWxnb3JpdGhtUglhbGdvcml0aG0SPwoGZGlnaXRzGAUgAS'
    'gOMicuZ29vZ2xlYXV0aC5NaWdyYXRpb25QYXlsb2FkLkRpZ2l0Q291bnRSBmRpZ2l0cxI4CgR0'
    'eXBlGAYgASgOMiQuZ29vZ2xlYXV0aC5NaWdyYXRpb25QYXlsb2FkLk90cFR5cGVSBHR5cGUSGA'
    'oHY291bnRlchgHIAEoA1IHY291bnRlciJ5CglBbGdvcml0aG0SGQoVQUxHT1JJVEhNX1VOU1BF'
    'Q0lGSUVEEAASEgoOQUxHT1JJVEhNX1NIQTEQARIUChBBTEdPUklUSE1fU0hBMjU2EAISFAoQQU'
    'xHT1JJVEhNX1NIQTUxMhADEhEKDUFMR09SSVRITV9NRDUQBCJVCgpEaWdpdENvdW50EhsKF0RJ'
    'R0lUX0NPVU5UX1VOU1BFQ0lGSUVEEAASEwoPRElHSVRfQ09VTlRfU0lYEAESFQoRRElHSVRfQ0'
    '9VTlRfRUlHSFQQAiJJCgdPdHBUeXBlEhgKFE9UUF9UWVBFX1VOU1BFQ0lGSUVEEAASEQoNT1RQ'
    'X1RZUEVfSE9UUBABEhEKDU9UUF9UWVBFX1RPVFAQAg==');
