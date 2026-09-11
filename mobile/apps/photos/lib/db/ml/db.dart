import "package:logging/logging.dart";
import "package:photos/db/ml/base.dart";
import "package:photos/db/ml/dart_db.dart";
import "package:photos/db/ml/rust_db.dart";
import "package:photos/src/rust/api/ml_db_api.dart" show decideMlDbBackend;

class MLDataDB {
  MLDataDB._();

  static final Logger _logger = Logger("MLDataDB");
  static bool? _useRust;

  static IMLDataDB<int> get instance =>
      isRustBackend ? RustMLDataDB.instance : DartMLDataDB.instance;
  static IMLDataDB<int> get localGalleryInstance => isRustBackend
      ? RustMLDataDB.localGalleryInstance
      : DartMLDataDB.localGalleryInstance;

  static bool get isRustBackend =>
      _useRust ??
      (throw StateError("MLDataDB.initialize must be called before use"));

  static void initialize({required bool preferRust}) {
    if (_useRust != null) return;
    final useRust = decideMlDbBackend(preferRust: preferRust);
    _useRust = useRust;
    _logger.info(
      "ML DB backend: ${useRust ? "rust" : "dart"} (wantsRust: $preferRust)",
    );
  }
}
