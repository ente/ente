import "package:logging/logging.dart";

class MiscUtil {
  final logger = Logger("MiscUtil");
  Future<double> getNonZeroDoubleWithRetry(
    double Function() getValue, {
    Duration retryInterval = const Duration(milliseconds: 8),
    String? id,
  }) async {
    final value = getValue();
    if (value != 0) {
      return value;
    } else {
      return await Future.delayed(retryInterval, () {
        if (id != null) {
          logger.info(
            "Retrying to get non-zero double value for $id after ${retryInterval.inMilliseconds} ms",
          );
        }
        return getNonZeroDoubleWithRetry(
          getValue,
          retryInterval: retryInterval,
        );
      });
    }
  }

  Future<dynamic> getNonNullValueWithRetry(
    dynamic Function() getValue, {
    Duration retryInterval = const Duration(milliseconds: 8),
    String? id,
  }) async {
    final value = getValue();
    if (value != null) {
      return value;
    } else {
      return await Future.delayed(retryInterval, () {
        if (id != null) {
          logger.info(
            "Retrying to get non-zero double value for $id after ${retryInterval.inMilliseconds} ms",
          );
        }
        return getNonNullValueWithRetry(getValue, retryInterval: retryInterval);
      });
    }
  }
}
