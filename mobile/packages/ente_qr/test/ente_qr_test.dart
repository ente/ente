import 'package:ente_qr/ente_qr.dart';
import 'package:ente_qr/ente_qr_method_channel.dart';
import 'package:ente_qr/ente_qr_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockEnteQrPlatform
    with MockPlatformInterfaceMixin
    implements EnteQrPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<QrScanResult> scanQrFromImage(
    String imagePath, {
    bool tryOriginalResolution = false,
  }) => Future.value(QrScanResult.error('Mock implementation'));

  @override
  Future<QrScanResults> scanAllQrFromImage(String imagePath) =>
      Future.value(QrScanResults.error('Mock implementation'));
}

void main() {
  final EnteQrPlatform initialPlatform = EnteQrPlatform.instance;

  test('$MethodChannelEnteQr is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelEnteQr>());
  });

  test('getPlatformVersion', () async {
    final EnteQr enteQrPlugin = EnteQr();
    final MockEnteQrPlatform fakePlatform = MockEnteQrPlatform();
    EnteQrPlatform.instance = fakePlatform;

    expect(await enteQrPlugin.getPlatformVersion(), '42');
  });
}
