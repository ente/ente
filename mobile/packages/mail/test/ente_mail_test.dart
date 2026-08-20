import 'package:ente_mail/ente_mail.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ente_mail_test');
  const composer = MailComposer(channel: channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('sends the narrow typed request', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return {'status': 'launched'};
        });

    final result = await composer.compose(
      const MailDraft(
        recipient: 'support@ente.io',
        subject: 'Logs',
        body: 'Attached',
        attachment: MailAttachment(
          path: '/tmp/logs.zip',
          mimeType: 'application/zip',
        ),
      ),
    );

    expect(result, isA<MailHandoffLaunched>());
    expect(received?.method, 'compose');
    expect(received?.arguments, {
      'recipient': 'support@ente.io',
      'subject': 'Logs',
      'body': 'Attached',
      'attachment': {'path': '/tmp/logs.zip', 'mimeType': 'application/zip'},
    });
  });

  test('rejects malformed native results', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return {'status': 'unavailable', 'reason': 'copied'};
        });

    await expectLater(
      composer.compose(const MailDraft(recipient: 'support@ente.io')),
      throwsA(
        isA<MailException>().having(
          (error) => error.code,
          'code',
          'invalidResponse',
        ),
      ),
    );
  });

  test('rejects relative attachment paths', () async {
    await expectLater(
      composer.compose(
        const MailDraft(
          recipient: 'support@ente.io',
          attachment: MailAttachment(
            path: 'logs.zip',
            mimeType: 'application/zip',
          ),
        ),
      ),
      throwsA(isA<MailException>()),
    );
  });
}
