import 'dart:convert';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:logging/logging.dart';
import 'package:pointycastle/export.dart' hide Algorithm;

final _logger = Logger('OtpAuthImportParser');

class IncorrectOtpAuthPasswordException implements Exception {
  const IncorrectOtpAuthPasswordException();
}

List<Code> parseOtpAuthExport(Uint8List fileBytes, {required String password}) {
  final outer = _decryptOuterArchive(fileBytes);
  final isBackup = outer.containsKey('WrappedData');
  final encryptedData = _bytes(outer[isBackup ? 'WrappedData' : 'Data']);
  final version = (outer['Version'] as num?)?.toDouble();
  final isLegacy =
      (isBackup && version == 1.0) || (!isBackup && version == 1.1);

  late final Uint8List decryptedData;
  if (isLegacy) {
    try {
      final ivSource = isBackup
          ? utf8.encode(outer['IV'] as String)
          : _bytes(outer['IV']);
      final key = _sha256(utf8.encode('${outer['Salt']}-$password'));
      decryptedData = _decryptAesCbc(
        encryptedData,
        key,
        _sha1(ivSource).sublist(0, 16),
      );
    } catch (_) {
      throw const IncorrectOtpAuthPasswordException();
    }
  } else if ((isBackup && version == 1.1) || (!isBackup && version == 1.2)) {
    decryptedData = _decryptRncCryptor(encryptedData, password);
  } else {
    throw FormatException('Unsupported OTP Auth export version: $version');
  }

  late final Map<String, Object?> root;
  try {
    root = _asMap(_unarchive(decryptedData));
  } catch (_) {
    if (isLegacy) throw const IncorrectOtpAuthPasswordException();
    rethrow;
  }
  final accounts = isBackup ? _backupAccounts(root) : [root];
  final codes = <Code>[];
  for (final account in accounts) {
    try {
      codes.add(_accountToCode(_asMap(account)));
    } catch (error, stackTrace) {
      _logger.warning('Skipping unsupported OTP Auth entry', error, stackTrace);
    }
  }
  return codes;
}

Map<String, Object?> _decryptOuterArchive(Uint8List fileBytes) {
  for (final magic in ['Authenticator', 'OTPAuth']) {
    try {
      final decrypted = _decryptAesCbc(
        fileBytes,
        _sha256(utf8.encode(magic)),
        Uint8List(16),
      );
      final archive = _asMap(_unarchive(decrypted));
      if (archive.containsKey('WrappedData') || archive.containsKey('Data')) {
        return archive;
      }
    } catch (_) {}
  }
  throw const FormatException('Invalid OTP Auth export');
}

List<Object?> _backupAccounts(Map<String, Object?> root) {
  final folders = root['Folders'];
  if (folders is! List) {
    throw const FormatException('Invalid OTP Auth backup');
  }
  return [
    for (final folder in folders)
      ...(_asMap(folder)['accounts'] as List? ?? const []),
  ];
}

Code _accountToCode(Map<String, Object?> account) {
  final type = switch (account['type']) {
    1 => Type.hotp,
    2 => Type.totp,
    _ => throw const FormatException('Unsupported OTP type'),
  };
  final algorithm = switch (account['algorithm']) {
    0 || 1 => Algorithm.sha1,
    2 => Algorithm.sha256,
    3 => Algorithm.sha512,
    _ => throw const FormatException('Unsupported OTP algorithm'),
  };
  final issuer = account['issuer'] as String;
  final label = account['label'] as String;
  final secret = base32.encode(_bytes(account['secret'])).replaceAll('=', '');
  final digits = (account['digits'] as int?) ?? 0;
  final period = (account['period'] as int?) ?? 0;
  final counter = (account['counter'] as int?) ?? 0;

  return Code.fromOTPAuthUrl(
    buildImportOtpUri(
      kind: type.name,
      issuer: Uri.encodeComponent(issuer),
      account: Uri.encodeComponent(label),
      secret: secret,
      algorithm: algorithm.name.toUpperCase(),
      digits: digits == 0 ? Code.defaultDigits : digits,
      period: period == 0 ? Code.defaultPeriod : period,
      counter: counter,
    ),
  );
}

Uint8List _decryptRncCryptor(Uint8List data, String password) {
  const headerLength = 34;
  const hmacLength = 32;
  if (data.length < headerLength + 16 + hmacLength ||
      data[0] != 3 ||
      data[1] != 1) {
    throw const FormatException('Invalid OTP Auth encryption');
  }

  final encryptionKey = _deriveRncCryptorKey(password, data.sublist(2, 10));
  final hmacKey = _deriveRncCryptorKey(password, data.sublist(10, 18));
  final authenticatedData = data.sublist(0, data.length - hmacLength);
  final expectedHmac = data.sublist(data.length - hmacLength);
  final actualHmac = (HMac(
    SHA256Digest(),
    64,
  )..init(KeyParameter(hmacKey))).process(authenticatedData);
  if (!_constantTimeEquals(actualHmac, expectedHmac)) {
    throw const IncorrectOtpAuthPasswordException();
  }

  return _decryptAesCbc(
    data.sublist(headerLength, data.length - hmacLength),
    encryptionKey,
    data.sublist(18, headerLength),
  );
}

Uint8List _deriveRncCryptorKey(String password, Uint8List salt) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64))
    ..init(Pbkdf2Parameters(salt, 10000, 32));
  final key = Uint8List(32);
  derivator.deriveKey(Uint8List.fromList(utf8.encode(password)), 0, key, 0);
  return key;
}

Uint8List _decryptAesCbc(Uint8List data, Uint8List key, Uint8List iv) {
  if (data.isEmpty || data.length % 16 != 0) {
    throw const FormatException('Invalid encrypted data');
  }
  final cipher = CBCBlockCipher(AESEngine())
    ..init(false, ParametersWithIV(KeyParameter(key), iv));
  final decrypted = Uint8List(data.length);
  for (var offset = 0; offset < data.length; offset += cipher.blockSize) {
    cipher.processBlock(data, offset, decrypted, offset);
  }

  final padding = decrypted.last;
  if (padding == 0 ||
      padding > cipher.blockSize ||
      decrypted
          .sublist(decrypted.length - padding)
          .any((value) => value != padding)) {
    throw const FormatException('Invalid encrypted data padding');
  }
  return decrypted.sublist(0, decrypted.length - padding);
}

Uint8List _sha1(List<int> data) =>
    SHA1Digest().process(Uint8List.fromList(data));

Uint8List _sha256(List<int> data) =>
    SHA256Digest().process(Uint8List.fromList(data));

bool _constantTimeEquals(Uint8List first, Uint8List second) {
  if (first.length != second.length) return false;
  var difference = 0;
  for (var index = 0; index < first.length; index++) {
    difference |= first[index] ^ second[index];
  }
  return difference == 0;
}

Object? _unarchive(Uint8List data) {
  return _KeyedArchive(_asMap(_BinaryPlistReader(data).parse())).root;
}

class _KeyedArchive {
  late final List<Object?> _objects;
  final _cache = <int, Object?>{};
  final _resolving = <int>{};
  final Map<String, Object?> archive;

  _KeyedArchive(this.archive) {
    if (archive[r'$archiver'] != 'NSKeyedArchiver' ||
        archive[r'$objects'] is! List) {
      throw const FormatException('Invalid keyed archive');
    }
    _objects = List<Object?>.from(archive[r'$objects'] as List);
  }

  Object? get root {
    final top = _asMap(archive[r'$top']);
    return _resolve(top['root']);
  }

  Object? _resolve(Object? value) {
    if (value is _PlistUid) return _resolveUid(value.value);
    if (value is Uint8List) return value;
    if (value is List) return value.map(_resolve).toList();
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _resolve(entry.value),
      };
    }
    return value;
  }

  Object? _resolveUid(int index) {
    if (index == 0) return null;
    if (index < 0 || index >= _objects.length || !_resolving.add(index)) {
      throw const FormatException('Invalid keyed archive reference');
    }
    if (_cache.containsKey(index)) {
      _resolving.remove(index);
      return _cache[index];
    }

    try {
      final raw = _objects[index];
      if (raw is! Map) {
        return _cache[index] = _resolve(raw);
      }
      final classUid = raw[r'$class'];
      if (classUid is! _PlistUid) {
        throw const FormatException('Missing keyed archive class');
      }
      final classMetadata = _asMap(_objects[classUid.value]);
      final className = classMetadata[r'$classname'];
      final result = switch (className) {
        'NSDictionary' || 'NSMutableDictionary' => _resolveDictionary(raw),
        'NSArray' ||
        'NSMutableArray' ||
        'NSSet' ||
        'NSMutableSet' => _resolve(raw['NS.objects']),
        'NSData' ||
        'NSMutableData' => _bytes(_resolve(raw['NS.data'] ?? raw['NS.bytes'])),
        'NSString' || 'NSMutableString' => _resolve(raw['NS.string']),
        'NSDate' => _resolve(raw['NS.time']),
        'ACOTPAccount' || 'ACOTPFolder' => {
          for (final entry in raw.entries)
            if (entry.key != r'$class')
              entry.key.toString(): _resolve(entry.value),
        },
        _ => throw FormatException(
          'Unsupported keyed archive class: $className',
        ),
      };
      _cache[index] = result;
      return result;
    } finally {
      _resolving.remove(index);
    }
  }

  Map<String, Object?> _resolveDictionary(Map raw) {
    final keys = _resolve(raw['NS.keys']) as List;
    final values = _resolve(raw['NS.objects']) as List;
    if (keys.length != values.length) {
      throw const FormatException('Invalid keyed archive dictionary');
    }
    return {
      for (var index = 0; index < keys.length; index++)
        keys[index] as String: values[index],
    };
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected a dictionary');
  return {for (final entry in value.entries) entry.key.toString(): entry.value};
}

Uint8List _bytes(Object? value) {
  if (value is Uint8List) return value;
  if (value is List<int>) return Uint8List.fromList(value);
  throw const FormatException('Expected binary data');
}

class _PlistUid {
  final int value;

  const _PlistUid(this.value);
}

class _Length {
  final int count;
  final int offset;

  const _Length(this.count, this.offset);
}

class _BinaryPlistReader {
  static const _header = [0x62, 0x70, 0x6c, 0x69, 0x73, 0x74, 0x30, 0x30];

  final Uint8List _data;
  late final ByteData _bytes;
  late final int _objectRefSize;
  late final List<int> _offsets;
  final _cache = <int, Object?>{};
  final _reading = <int>{};

  _BinaryPlistReader(this._data);

  Object? parse() {
    _bytes = ByteData.sublistView(_data);
    if (_data.length < _header.length + 32 ||
        !_header.indexed.every((entry) => _data[entry.$1] == entry.$2)) {
      throw const FormatException('Invalid binary plist');
    }

    final trailerOffset = _data.length - 32;
    final offsetSize = _readByte(trailerOffset + 6);
    _objectRefSize = _readByte(trailerOffset + 7);
    final objectCount = _readUInt(trailerOffset + 8, 8);
    final rootObject = _readUInt(trailerOffset + 16, 8);
    final offsetTableOffset = _readUInt(trailerOffset + 24, 8);

    if (offsetSize < 1 ||
        offsetSize > 8 ||
        _objectRefSize < 1 ||
        _objectRefSize > 8 ||
        objectCount < 1 ||
        objectCount > _data.length ||
        rootObject >= objectCount ||
        offsetTableOffset < _header.length ||
        offsetTableOffset >= trailerOffset ||
        offsetTableOffset + (objectCount * offsetSize) > trailerOffset) {
      throw const FormatException('Invalid binary plist trailer');
    }

    _offsets = List.generate(
      objectCount,
      (index) =>
          _readUInt(offsetTableOffset + (index * offsetSize), offsetSize),
    );
    if (_offsets.any(
      (offset) => offset < _header.length || offset >= offsetTableOffset,
    )) {
      throw const FormatException('Invalid binary plist offset table');
    }

    return _readObject(rootObject);
  }

  Object? _readObject(int objectId) {
    if (objectId < 0 || objectId >= _offsets.length) {
      throw const FormatException('Invalid binary plist reference');
    }
    if (_cache.containsKey(objectId)) return _cache[objectId];
    if (!_reading.add(objectId)) {
      throw const FormatException('Recursive binary plist reference');
    }

    try {
      final offset = _offsets[objectId];
      final marker = _readByte(offset);
      final type = marker >> 4;
      final info = marker & 0x0F;
      final result = switch (type) {
        0x0 => _readSimple(info),
        0x1 => _readUInt(offset + 1, _intSize(info)),
        0x2 => _readReal(offset + 1, _intSize(info)),
        0x4 => _readData(offset, info),
        0x5 => _readAscii(offset, info),
        0x6 => _readUtf16(offset, info),
        0x8 => _PlistUid(_readUInt(offset + 1, info + 1)),
        0xA => _readArray(offset, info),
        0xD => _readDictionary(offset, info),
        _ => throw FormatException('Unsupported binary plist type: $type'),
      };
      _cache[objectId] = result;
      return result;
    } finally {
      _reading.remove(objectId);
    }
  }

  Object? _readSimple(int info) {
    return switch (info) {
      0x0 => null,
      0x8 => false,
      0x9 => true,
      _ => throw FormatException('Unsupported binary plist value: $info'),
    };
  }

  double _readReal(int offset, int length) {
    _checkRange(offset, length);
    return switch (length) {
      4 => _bytes.getFloat32(offset, Endian.big),
      8 => _bytes.getFloat64(offset, Endian.big),
      _ => throw FormatException('Unsupported binary plist real size: $length'),
    };
  }

  Uint8List _readData(int offset, int info) {
    final length = _readLength(offset, info);
    _checkRange(length.offset, length.count);
    return _data.sublist(length.offset, length.offset + length.count);
  }

  String _readAscii(int offset, int info) {
    final length = _readLength(offset, info);
    _checkRange(length.offset, length.count);
    return ascii.decode(
      _data.sublist(length.offset, length.offset + length.count),
    );
  }

  String _readUtf16(int offset, int info) {
    final length = _readLength(offset, info);
    final byteLength = length.count * 2;
    _checkRange(length.offset, byteLength);
    final buffer = StringBuffer();
    for (var index = 0; index < byteLength; index += 2) {
      buffer.writeCharCode(_bytes.getUint16(length.offset + index, Endian.big));
    }
    return buffer.toString();
  }

  List<Object?> _readArray(int offset, int info) {
    final length = _readLength(offset, info);
    _checkRange(length.offset, length.count * _objectRefSize);
    return [
      for (var index = 0; index < length.count; index++)
        _readObject(
          _readUInt(length.offset + (index * _objectRefSize), _objectRefSize),
        ),
    ];
  }

  Map<String, Object?> _readDictionary(int offset, int info) {
    final length = _readLength(offset, info);
    final valuesOffset = length.offset + (length.count * _objectRefSize);
    _checkRange(length.offset, length.count * _objectRefSize * 2);
    return {
      for (var index = 0; index < length.count; index++)
        _readObject(
              _readUInt(
                length.offset + (index * _objectRefSize),
                _objectRefSize,
              ),
            )
            as String: _readObject(
          _readUInt(valuesOffset + (index * _objectRefSize), _objectRefSize),
        ),
    };
  }

  _Length _readLength(int offset, int info) {
    if (info < 0xF) return _Length(info, offset + 1);

    final marker = _readByte(offset + 1);
    if (marker >> 4 != 0x1) {
      throw const FormatException('Invalid binary plist length');
    }
    final intSize = _intSize(marker & 0x0F);
    return _Length(_readUInt(offset + 2, intSize), offset + 2 + intSize);
  }

  int _intSize(int info) {
    if (info > 3) throw const FormatException('Unsupported binary plist size');
    return 1 << info;
  }

  int _readByte(int offset) {
    _checkRange(offset, 1);
    return _data[offset];
  }

  int _readUInt(int offset, int length) {
    _checkRange(offset, length);
    var value = 0;
    for (var index = 0; index < length; index++) {
      value = (value << 8) | _data[offset + index];
    }
    return value;
  }

  void _checkRange(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > _data.length) {
      throw const FormatException('Truncated binary plist');
    }
  }
}
