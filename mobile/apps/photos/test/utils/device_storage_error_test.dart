import "dart:io";

import "package:dio/dio.dart";
import "package:flutter/services.dart" show PlatformException;
import "package:flutter_test/flutter_test.dart";
import "package:photos/core/errors.dart";
import "package:photos/utils/device_storage_error.dart";

void main() {
  group("isDeviceStorageFullError", () {
    test("classifies Dart ENOSPC FileSystemException", () {
      // What dart:io throws when a write hits "No space left on device".
      const error = FileSystemException(
        "writeFrom failed",
        "/tmp/upload_file_1_file.encrypted",
        OSError("No space left on device", 28),
      );
      expect(isDeviceStorageFullError(error), isTrue);
    });

    test("classifies Windows ERROR_DISK_FULL FileSystemException", () {
      const error = FileSystemException(
        "writeFrom failed",
        "C:\\tmp\\file.encrypted",
        OSError("There is not enough space on the disk.", 112),
      );
      expect(isDeviceStorageFullError(error), isTrue);
    });

    test("classifies a bare ENOSPC OSError", () {
      expect(
        isDeviceStorageFullError(const OSError("No space left on device", 28)),
        isTrue,
      );
    });

    test(
      "classifies NSFileWriteOutOfSpaceError from photo_manager "
      "(NSCocoaErrorDomain 640)",
      () {
        // PMResultHandler.replyError formats NSError as "<domain> (<code>)".
        final error = PlatformException(
          code: "NSCocoaErrorDomain (640)",
          message:
              "You can't save the file "
              "“IMG_0001.HEIC” because the volume is out of space.",
        );
        expect(isDeviceStorageFullError(error), isTrue);
      },
    );

    test("classifies native POSIX ENOSPC (NSPOSIXErrorDomain 28)", () {
      final error = PlatformException(
        code: "NSPOSIXErrorDomain (28)",
        message: "No space left on device",
      );
      expect(isDeviceStorageFullError(error), isTrue);
    });

    test(
      "classifies PHPhotosErrorNotEnoughSpace (PHPhotosErrorDomain 3305)",
      () {
        final error = PlatformException(
          code: "PHPhotosErrorDomain (3305)",
          message: "Not enough space to perform the requested change",
        );
        expect(isDeviceStorageFullError(error), isTrue);
      },
    );

    test("classifies NSError description embedded in the message", () {
      final error = PlatformException(
        code: "PMFileHelper",
        message:
            "The operation couldn’t be completed. "
            "(NSCocoaErrorDomain error 640.)",
      );
      expect(isDeviceStorageFullError(error), isTrue);
    });

    test("classifies DioException wrapping an ENOSPC FileSystemException", () {
      final error = DioException(
        requestOptions: RequestOptions(path: "/files"),
        error: const FileSystemException(
          "write failed",
          "/tmp/part",
          OSError("No space left on device", 28),
        ),
      );
      expect(isDeviceStorageFullError(error), isTrue);
    });

    test("classifies the canonical exception and error types", () {
      expect(isDeviceStorageFullError(const DeviceStorageFullException()),
          isTrue);
      expect(isDeviceStorageFullError(DeviceStorageFullError()), isTrue);
      expect(
        isDeviceStorageFullError(
          DeviceStorageFullError(
            const FileSystemException(
              "write failed",
              "/tmp/part",
              OSError("No space left on device", 28),
            ),
          ),
        ),
        isTrue,
      );
    });

    test("does not classify other file system errors", () {
      // ENOENT
      expect(
        isDeviceStorageFullError(
          const FileSystemException(
            "open failed",
            "/tmp/missing",
            OSError("No such file or directory", 2),
          ),
        ),
        isFalse,
      );
      // No OS error at all
      expect(
        isDeviceStorageFullError(const FileSystemException("closed")),
        isFalse,
      );
    });

    test("does not classify PhotoKit network or resource errors", () {
      expect(
        isDeviceStorageFullError(
          PlatformException(
            code: "PHPhotosErrorDomain (3169)",
            message: "A network error occurred",
          ),
        ),
        isFalse,
      );
      expect(
        isDeviceStorageFullError(
          PlatformException(
            code: "PHPhotosErrorDomain (3302)",
            message: "Asset resource validation failed",
          ),
        ),
        isFalse,
      );
    });

    test("does not classify network or remote-quota failures", () {
      expect(
        isDeviceStorageFullError(
          DioException(
            requestOptions: RequestOptions(path: "/files"),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
        isFalse,
      );
      // Remote (plan) storage quota is a different condition.
      expect(isDeviceStorageFullError(StorageLimitExceededError()), isFalse);
      expect(
        isDeviceStorageFullError(const SocketException("connection refused")),
        isFalse,
      );
    });
  });

  group("DeviceStorageFullError", () {
    test("preserves the original error for diagnostics", () {
      const cause = FileSystemException(
        "writeFrom failed",
        "/tmp/upload_file_1_file.encrypted",
        OSError("No space left on device", 28),
      );
      final error = DeviceStorageFullError(cause);
      expect(error.cause, same(cause));
      expect(error.toString(), contains("No space left on device"));
      expect(error.toString(), contains("errno = 28"));
    });

    test("is a handled sync error", () {
      expect(isHandledSyncError(DeviceStorageFullError()), isTrue);
    });
  });
}
