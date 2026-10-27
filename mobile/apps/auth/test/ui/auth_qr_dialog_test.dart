import 'dart:io';

import 'package:ente_auth/ui/components/auth_qr_dialog.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

const _fileName = 'ente_auth_qr_synthetic.png';
const _data = 'otpauth://totp/Synthetic:test?secret=JBSWY3DPEHPK3PXP';

Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: Scaffold(
        body: AuthQrDialog(
          data: _data,
          title: 'Synthetic issuer',
          subtitle: 'Synthetic account',
          shareFileName: _fileName,
          shareText: 'Synthetic QR code',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('keeps the QR visible and gates sharing by the native platform', (
    tester,
  ) async {
    await _pumpDialog(tester);

    expect(find.text('Synthetic issuer'), findsOneWidget);
    expect(find.text('Synthetic account'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    final sheet = tester.widget<BottomSheetComponent>(
      find.byType(BottomSheetComponent),
    );
    if (!kIsWeb && Platform.isLinux) {
      expect(sheet.actions, isEmpty);
      expect(find.text('Share'), findsNothing);
    } else {
      expect(sheet.actions, hasLength(1));
      expect(find.text('Share'), findsOneWidget);
    }

    await tester.tap(find.byType(QrImageView));
    await tester.pump();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native sharing only creates a PNG on supported platforms', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('auth-qr-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    var temporaryDirectoryRequests = 0;
    final shares = <MethodCall>[];
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathChannel, (call) async {
      expect(call.method, 'getTemporaryDirectory');
      temporaryDirectoryRequests++;
      return directory.path;
    });
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      shares.add(call);
      return 'test';
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(pathChannel, null);
      messenger.setMockMethodCallHandler(shareChannel, null);
    });

    await _pumpDialog(tester);
    if (Platform.isLinux) {
      expect(find.text('Share'), findsNothing);
      // Exercise the defensive guard even though its button is hidden.
      final state = tester.state<AuthQrDialogState>(find.byType(AuthQrDialog));
      await tester.runAsync(state.shareQrCode);
      expect(directory.listSync(), isEmpty);
      expect(temporaryDirectoryRequests, 0);
      expect(shares, isEmpty);
    } else {
      final button = tester.widget<ButtonComponent>(
        find.widgetWithText(ButtonComponent, 'Share'),
      );
      await tester.runAsync(() async => button.onTap!());
      expect(temporaryDirectoryRequests, 1);
      final png = File('${directory.path}/$_fileName');
      expect(png.existsSync(), isTrue);
      expect(png.readAsBytesSync().take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(shares, hasLength(1));
      expect(shares.single.method, 'share');
      expect(shares.single.arguments['paths'], [png.path]);
      expect(shares.single.arguments['text'], 'Synthetic QR code');
    }
    expect(tester.takeException(), isNull);
  }, skip: kIsWeb);
}
