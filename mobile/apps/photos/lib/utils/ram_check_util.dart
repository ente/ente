import "package:ente_photos_platform/ente_photos_platform.dart";

// Total device RAM in MB.
int? deviceTotalRAM;

bool get enoughRamForLocalIndexing =>
    deviceTotalRAM == null || deviceTotalRAM! >= 5 * 1024;

bool get hasLessThan5GBRAM =>
    deviceTotalRAM != null && deviceTotalRAM! < 5 * 1024;

bool get enoughRamForLocalGalleryLocalIndexing =>
    deviceTotalRAM == null || deviceTotalRAM! > 3 * 1024;

Future<int?> checkDeviceTotalRAM() async {
  if (deviceTotalRAM != null) return deviceTotalRAM;
  try {
    final memory = await DeviceHealthClient.instance.getMemorySnapshot();
    if (memory.status == DeviceSignalStatus.available) {
      deviceTotalRAM = memory.totalBytes! ~/ (1024 * 1024);
    }
  } catch (_) {
    return null;
  }
  return deviceTotalRAM;
}
