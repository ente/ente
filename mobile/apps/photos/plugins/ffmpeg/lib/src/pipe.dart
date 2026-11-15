import 'dart:ffi';

import 'package:ffi/ffi.dart';

final _mkfifo = DynamicLibrary.process()
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Uint32),
      int Function(Pointer<Utf8>, int)
    >('mkfifo');

void createPipe(String path) {
  if (path.contains('\u0000')) {
    throw ArgumentError('Pipe paths cannot contain NUL characters.');
  }
  final code = using(
    (arena) => _mkfifo(path.toNativeUtf8(allocator: arena), 0x180),
  );
  if (code != 0) throw StateError('Could not create a pipe at $path.');
}
