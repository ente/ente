import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import "package:photos/services/filter/filter.dart";

class TypeFilter extends Filter {
  final FileType type;
  final bool reverse;

  TypeFilter(this.type, {this.reverse = false});

  @override
  bool filter(EnteFile file) {
    return reverse ? file.fileType != type : file.fileType == type;
  }
}
