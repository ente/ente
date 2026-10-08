import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:ente_crypto/ente_crypto.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart'
    show isFileSystemPathMissing;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:photos/core/cache/video_cache_manager.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/module/download/decrypt.dart';
import 'package:photos/module/download/file.dart';
import 'package:photos/module/download/manager.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/utils/file_key.dart';

class ProgressiveVideoStream {
  static final _logger = Logger('ProgressiveVideo');

  ProgressiveVideoStream(this.file, {required this.onProgress}) {
    _source.future.ignore();
    _failure.future.ignore();
    _commands.future.ignore();
  }

  final EnteFile file;
  final void Function(int, int) onProgress;
  final _source = Completer<String?>();
  final _failure = Completer<void>();
  final _commands = Completer<SendPort>();
  final _exited = Completer<void>();
  final _events = ReceivePort();
  Isolate? _worker;
  Directory? _directory;
  Future<void>? _opening, _closing;
  bool _complete = false;
  String? url;

  Future<void> get failure => _failure.future;

  Future<String?> open() async {
    _opening = _start();
    await _opening;
    return _source.future;
  }

  Future<void> _start() async {
    final extension = p.extension(file.title ?? '').toLowerCase();
    final size = file.fileSize;
    if (file.fileType != FileType.video ||
        !{'.mp4', '.mov', '.m4v'}.contains(extension) ||
        size == null ||
        size <= 0 ||
        file.uploadedFileID == null ||
        file.collectionID == null ||
        file.fileDecryptionHeader == null ||
        CollectionsService.instance.isSharedPublicLink(file.collectionID!)) {
      _source.complete(null);
      return;
    }
    if (await VideoCacheManager.instance.getFileFromCache(file.downloadUrl) !=
        null) {
      if (!_source.isCompleted) {
        _source.complete(null);
      }
      return;
    }
    if (_closing != null) {
      return;
    }
    _directory = await Directory(
      Configuration.instance.getTempDirectory(),
    ).createTemp('video-');
    if (_closing != null) {
      return;
    }
    final output = '${_directory!.path}/original$extension';
    _events.listen((dynamic event) {
      switch (event) {
        case final SendPort port:
          _commands.complete(port);
        case (source: final String source):
          if (_closing == null && !_source.isCompleted) {
            url = source;
            _source.complete(source);
          }
        case (complete: true):
          _complete = true;
        case (unsupported: true):
          if (!_source.isCompleted) {
            _source.complete(null);
          }
        case (error: final String kind):
          _fail(StateError('Progressive video failed ($kind)'));
        case null:
          _exited.complete();
          if (!_commands.isCompleted) {
            _commands.completeError(StateError('Video worker did not start'));
          }
          if (_closing == null) {
            _fail(StateError('Video worker exited'));
          }
      }
    });
    _worker = await Isolate.spawn(_runVideoServer, (
      events: _events.sendPort,
      encryptedPath: getEncryptedFilePath(file),
      resumablePath: DownloadManager.encryptedFilePath(file.uploadedFileID!),
      output: output,
      size: size,
      header: CryptoUtil.base642bin(file.fileDecryptionHeader!),
      key: getFileKey(file),
    ), onExit: _events.sendPort);
    final commands = await _commands.future;
    if (_closing == null) {
      unawaited(_downloadFile(commands, size));
    }
  }

  void playbackFailed() => _fail(StateError('Progressive player failed'));

  void _fail(Object error) {
    if (!_source.isCompleted) {
      _source.completeError(error);
    }
    if (!_failure.isCompleted) {
      _failure.completeError(error);
    }
  }

  Future<void> _downloadFile(SendPort commands, int size) async {
    try {
      final cached = await getFileFromServer(
        file,
        throwOnDecryptionFailure: true,
        progressCallback: (count, _) {
          if (_closing == null) {
            onProgress(count, size);
          }
        },
      );
      if (_closing != null || _complete) {
        return;
      }
      if (cached == null) {
        _fail(StateError('Video download failed'));
      } else {
        commands.send(cached.path);
      }
    } catch (error) {
      if (_closing == null && !_complete) {
        _fail(error);
      }
    }
  }

  Future<void> dispose() => _closing ??= _dispose();

  Future<void> _dispose() async {
    if (!_source.isCompleted) {
      _source.complete(null);
    }
    if (!_failure.isCompleted) {
      _failure.complete();
    }
    await _opening?.catchError((Object _) {});
    if (_worker != null) {
      if (_commands.isCompleted && !_exited.isCompleted) {
        (await _commands.future).send(null);
      }
      try {
        await _exited.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        _worker!.kill(priority: Isolate.immediate);
        await _exited.future;
      }
    }
    _events.close();
    try {
      await _directory?.delete(recursive: true);
    } on FileSystemException catch (error) {
      _logger.warning('Cleanup failed (${error.runtimeType})');
    }
  }
}

typedef _Download = ({
  SendPort events,
  String encryptedPath,
  String resumablePath,
  String output,
  int size,
  Uint8List header,
  Uint8List key,
});

Future<void> _runVideoServer(_Download download) =>
    _VideoServer(download).run();

class _CiphertextGone implements Exception {
  const _CiphertextGone();
}

class _VideoServer {
  _VideoServer(this.download);
  final _Download download;
  final _commands = ReceivePort();
  final _stopped = Completer<void>();
  Completer<void> _changed = Completer<void>();
  HttpServer? _server;
  int _written = 0;
  bool _closed = false;
  String? _cachedPath;

  int get _length =>
      download.size -
      ((download.size + decryptionChunkSize - 1) ~/ decryptionChunkSize) *
          (decryptionChunkSize - encryptionChunkSize);

  void _wakeReaders() {
    _changed.complete();
    _changed = Completer<void>();
  }

  Future<void> run() async {
    download.events.send(_commands.sendPort);
    _commands.listen((command) {
      if (command is String) {
        _cachedPath = command;
        return;
      }
      _closed = true;
      _wakeReaders();
      if (!_stopped.isCompleted) {
        _stopped.complete();
      }
    });
    RandomAccessFile? output;
    try {
      CryptoUtil.init();
      output = File(download.output).openSync(mode: FileMode.write);
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final random = Random.secure();
      final path =
          '/${List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}${p.extension(download.output)}';
      _server!.listen((request) => unawaited(_serve(request, path)));
      try {
        await for (final bytes in decryptFileStream(
          _encryptedBytes(),
          header: download.header,
          key: download.key,
        )) {
          if (_closed) {
            return;
          }
          if (_written == 0 && !_hasFrontMovie(bytes)) {
            download.events.send((unsupported: true));
            return;
          }
          output.writeFromSync(bytes);
          final first = _written == 0;
          _written += bytes.length;
          _wakeReaders();
          if (first) {
            download.events.send((
              source: 'http://127.0.0.1:${_server!.port}$path',
            ));
          }
        }
      } on _CiphertextGone {
        if (_written == 0) {
          download.events.send((unsupported: true));
          return;
        }
        await for (final bytes in File(_cachedPath!).openRead(_written)) {
          if (_closed) {
            return;
          }
          output.writeFromSync(bytes);
          _written += bytes.length;
          _wakeReaders();
        }
      }
      if (_closed) {
        return;
      }
      if (_written != _length) {
        throw const FormatException('Incomplete video');
      }
      output.closeSync();
      output = null;
      download.events.send((complete: true));
      await _stopped.future;
    } catch (error) {
      if (!_closed) {
        download.events.send((error: error.runtimeType.toString()));
      }
    } finally {
      _closed = true;
      _wakeReaders();
      await _server?.close(force: true);
      output?.closeSync();
      _commands.close();
    }
  }

  Stream<List<int>> _encryptedBytes() async* {
    var offset = 0;
    while (offset < download.size && !_closed) {
      final count = min(decryptionChunkSize, download.size - offset);
      final partOffset = offset % DownloadManager.downloadChunkSize;
      final partPath = DownloadManager.chunkFilePath(
        download.resumablePath,
        offset ~/ DownloadManager.downloadChunkSize + 1,
      );
      final bytes =
          await _readAvailable(
            partPath,
            partOffset,
            min(count, DownloadManager.downloadChunkSize - partOffset),
          ) ??
          await _readAvailable(download.resumablePath, offset, count) ??
          await _readAvailable(download.encryptedPath, offset, count);
      if (bytes != null) {
        offset += bytes.length;
        yield bytes;
      } else if (_cachedPath != null) {
        throw const _CiphertextGone();
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  Future<Uint8List?> _readAvailable(String path, int offset, int count) async {
    try {
      final input = await File(path).open();
      try {
        await input.setPosition(offset);
        final bytes = await input.read(count);
        return bytes.isEmpty ? null : bytes;
      } finally {
        await input.close();
      }
    } on FileSystemException catch (error) {
      if (!isFileSystemPathMissing(error)) {
        rethrow;
      }
      return null;
    }
  }

  Future<void> _serve(HttpRequest request, String path) async {
    final response = request.response;
    try {
      if (request.uri.path != path || request.headers.host != '127.0.0.1') {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final header = request.method == 'GET'
          ? request.headers.value('Range')
          : null;
      final range = header == null
          ? null
          : RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header);
      var start = 0;
      var end = _length;
      if (range != null) {
        final left = int.tryParse(range[1]!);
        final right = int.tryParse(range[2]!);
        if (left == null) {
          start = max(0, end - (right ?? 0));
        } else {
          start = left;
          if (right != null) {
            end = min(end, right + 1);
          }
        }
        if (start >= end) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set('Content-Range', 'bytes */$_length');
          return;
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          'Content-Range',
          'bytes $start-${end - 1}/$_length',
        );
      }
      response.headers
        ..set('Accept-Ranges', 'bytes')
        ..set(
          'Content-Type',
          download.output.endsWith('.mov') ? 'video/quicktime' : 'video/mp4',
        )
        ..set('Cache-Control', 'no-store')
        ..set('X-Content-Type-Options', 'nosniff');
      response.contentLength = end - start;
      if (request.method == 'HEAD') {
        return;
      }
      while (start < end && !_closed) {
        if (start >= _written) {
          await _changed.future;
        } else {
          final available = min(_written, end);
          await response.addStream(
            File(download.output).openRead(start, available),
          );
          start = available;
        }
      }
    } catch (_) {
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }
}

bool _hasFrontMovie(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 0;
  while (offset + 8 <= bytes.length) {
    var size = data.getUint32(offset);
    final type = data.getUint32(offset + 4);
    var headerSize = 8;
    if (size == 1) {
      if (offset + 16 > bytes.length) {
        return false;
      }
      size = data.getUint64(offset + 8);
      headerSize = 16;
    }
    if (size < headerSize || size > bytes.length - offset) {
      return false;
    }
    if (type == 0x6d6f6f76) {
      return true;
    }
    if (type == 0x6d646174) {
      return false;
    }
    offset += size;
  }
  return false;
}
