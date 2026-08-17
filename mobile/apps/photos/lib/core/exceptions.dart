// Expected runtime errors may be logged, but should not be reported as crashes.
abstract interface class LocallyHandledError {}

class WidgetUnmountedException implements Exception {
  final String? message;

  WidgetUnmountedException([this.message]);

  @override
  String toString() => message != null
      ? 'WidgetUnmountedException: $message'
      : 'WidgetUnmountedException';
}
