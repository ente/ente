import 'package:flutter/services.dart';

enum DeviceFolderTransferOperation { add, move }

enum DeviceFolderTransferFailure {
  cancelled,
  missingSource,
  ineligibleDestination,
  unsupported,
  permissionDenied,
  failed,
}

class DeviceFolderTransferResult {
  const DeviceFolderTransferResult({
    required this.destinations,
    required this.failures,
  });

  final Map<String, String> destinations;
  final Map<String, DeviceFolderTransferFailure> failures;

  bool get wasCancelled =>
      destinations.isEmpty &&
      failures.isNotEmpty &&
      failures.values.every(
        (failure) => failure == DeviceFolderTransferFailure.cancelled,
      );

  factory DeviceFolderTransferResult.fromChannelMap(Map<dynamic, dynamic> map) {
    final destinations = Map<String, String>.from(map['destinations'] as Map);
    final rawFailures = map['failures'] as Map<dynamic, dynamic>;
    return DeviceFolderTransferResult(
      destinations: destinations,
      failures: rawFailures.map(
        (key, value) => MapEntry(
          key as String,
          DeviceFolderTransferFailure.values.firstWhere(
            (failure) => failure.name == value,
            orElse: () => DeviceFolderTransferFailure.failed,
          ),
        ),
      ),
    );
  }
}

class DeviceFolderTransferClient {
  const DeviceFolderTransferClient();

  static const _channel = MethodChannel(
    'io.ente.photos.platform/device_folder_transfer',
  );

  Future<Set<DeviceFolderTransferOperation>> supportedOperations({
    String? sourceFolderID,
  }) async {
    final operations = await _channel.invokeListMethod<String>(
      'deviceFolderTransfer.supportedOperations',
      {'sourceFolderID': sourceFolderID},
    );
    return DeviceFolderTransferOperation.values
        .where((operation) => operations?.contains(operation.name) ?? false)
        .toSet();
  }

  Future<Set<String>> eligibleDestinationIDs({
    required DeviceFolderTransferOperation operation,
    required String? sourceFolderID,
    required List<String> candidateFolderIDs,
  }) async {
    final ids = await _channel
        .invokeListMethod<String>('deviceFolderTransfer.eligibleDestinations', {
          'operation': operation.name,
          'sourceFolderID': sourceFolderID,
          'candidateFolderIDs': candidateFolderIDs,
        });
    return ids?.toSet() ?? {};
  }

  Future<DeviceFolderTransferResult> transfer({
    required DeviceFolderTransferOperation operation,
    required String? sourceFolderID,
    required String targetFolderID,
    required List<String> sourceLocalIDs,
  }) async {
    final result = await _channel
        .invokeMapMethod<dynamic, dynamic>('deviceFolderTransfer.transfer', {
          'operation': operation.name,
          'sourceFolderID': sourceFolderID,
          'targetFolderID': targetFolderID,
          'sourceLocalIDs': sourceLocalIDs,
        });
    if (result == null) {
      throw PlatformException(code: 'device_folder_transfer_invalid_result');
    }
    return DeviceFolderTransferResult.fromChannelMap(result);
  }
}
