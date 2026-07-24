import "dart:convert";
import "dart:typed_data";

final class ProtoField {
  const ProtoField.varint(this.number, this.varint) : bytes = null;

  const ProtoField.bytes(this.number, this.bytes) : varint = null;

  const ProtoField.skipped(this.number) : varint = null, bytes = null;

  final int number;
  final int? varint;
  final Uint8List? bytes;
}

final class ProtoReader {
  ProtoReader(this._bytes);

  final Uint8List _bytes;
  var _offset = 0;

  bool get hasNext => _offset < _bytes.length;

  ProtoField readField() {
    final tag = _readVarint();
    final number = tag >> 3;
    if (number == 0) {
      throw const FormatException("Invalid protobuf field number");
    }
    final wireType = tag & 7;
    switch (wireType) {
      case 0:
        return ProtoField.varint(number, _readVarint());
      case 1:
        _skip(8);
        return ProtoField.skipped(number);
      case 2:
        final length = _readVarint();
        final end = _offset + length;
        if (length < 0 || end > _bytes.length) {
          throw const FormatException("Truncated protobuf field");
        }
        final value = Uint8List.fromList(_bytes.sublist(_offset, end));
        _offset = end;
        return ProtoField.bytes(number, value);
      case 5:
        _skip(4);
        return ProtoField.skipped(number);
      default:
        throw FormatException("Unsupported protobuf wire type $wireType");
    }
  }

  int _readVarint() {
    var value = 0;
    var shift = 0;
    while (_offset < _bytes.length && shift <= 63) {
      final byte = _bytes[_offset++];
      value |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) {
        return value;
      }
      shift += 7;
    }
    throw const FormatException("Invalid protobuf varint");
  }

  void _skip(int length) {
    _offset += length;
    if (_offset > _bytes.length) {
      throw const FormatException("Truncated protobuf field");
    }
  }
}

final class ProtoWriter {
  final _output = BytesBuilder(copy: false);

  void writeVarint(int field, int value) {
    _writeVarint(field << 3);
    _writeVarint(value);
  }

  void writeBytes(int field, List<int> value) {
    _writeVarint((field << 3) | 2);
    _writeVarint(value.length);
    _output.add(value);
  }

  void writeString(int field, String value) {
    writeBytes(field, utf8.encode(value));
  }

  Uint8List takeBytes() => _output.takeBytes();

  void _writeVarint(int value) {
    var remaining = value;
    while (remaining >= 0x80) {
      _output.addByte((remaining & 0x7f) | 0x80);
      remaining >>= 7;
    }
    _output.addByte(remaining);
  }
}
