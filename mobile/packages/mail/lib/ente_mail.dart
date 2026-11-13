import 'package:flutter/services.dart';

enum MailUnavailableReason {
  unsupportedPlatform,
  noMailClient,
  attachmentComposerUnavailable,
  attachmentMissing,
  attachmentUnreadable,
  attachmentTooLarge,
  composerBusy,
  presentationFailed,
}

sealed class MailComposeResult {
  const MailComposeResult();
}

final class MailHandoffLaunched extends MailComposeResult {
  const MailHandoffLaunched();
}

final class MailUnavailable extends MailComposeResult {
  const MailUnavailable(this.reason);

  final MailUnavailableReason reason;
}

final class MailException implements Exception {
  const MailException(this.code, this.message, {this.details, this.cause});

  final String code;
  final String message;
  final Object? details;
  final Object? cause;

  @override
  String toString() => 'MailException($code, $message)';
}

final class MailAttachment {
  const MailAttachment({required this.path, required this.mimeType});

  final String path;
  final String mimeType;

  Map<String, Object> get _channelValue => {'path': path, 'mimeType': mimeType};
}

final class MailDraft {
  const MailDraft({
    required this.recipient,
    this.subject = '',
    this.body = '',
    this.attachment,
  });

  final String recipient;
  final String subject;
  final String body;
  final MailAttachment? attachment;

  Map<String, Object?> get _channelValue => {
    'recipient': recipient,
    'subject': subject,
    'body': body,
    'attachment': ?attachment?._channelValue,
  };
}

final class MailComposer {
  const MailComposer({
    MethodChannel channel = const MethodChannel('io.ente.mail/composer'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<MailComposeResult> compose(MailDraft draft) async {
    _validate(draft);
    final Map<Object?, Object?>? response;
    try {
      response = await _channel.invokeMapMethod<Object?, Object?>(
        'compose',
        draft._channelValue,
      );
    } on MissingPluginException {
      return const MailUnavailable(MailUnavailableReason.unsupportedPlatform);
    } on PlatformException catch (error) {
      throw MailException(
        error.code,
        error.message ?? 'Mail composition failed',
        details: error.details,
        cause: error,
      );
    }
    return _parseResult(response);
  }
}

MailComposeResult _parseResult(Map<Object?, Object?>? response) {
  if (response == null) {
    throw const MailException('invalidResponse', 'Native result is missing');
  }
  switch (response['status']) {
    case 'launched':
      return const MailHandoffLaunched();
    case 'unavailable':
      final reasonName = response['reason'];
      if (reasonName is! String) {
        throw const MailException(
          'invalidResponse',
          'Unavailable result has no reason',
        );
      }
      final reason = MailUnavailableReason.values
          .where((candidate) => candidate.name == reasonName)
          .firstOrNull;
      if (reason == null) {
        throw MailException(
          'invalidResponse',
          'Unknown unavailable reason: $reasonName',
        );
      }
      return MailUnavailable(reason);
    default:
      throw const MailException(
        'invalidResponse',
        'Native result has an unknown status',
      );
  }
}

void _validate(MailDraft draft) {
  if (draft.recipient.isEmpty || draft.recipient != draft.recipient.trim()) {
    throw const MailException('invalidDraft', 'Recipient is invalid');
  }
  if (_containsNull(draft.recipient) ||
      _containsNull(draft.subject) ||
      _containsNull(draft.body)) {
    throw const MailException('invalidDraft', 'Mail text contains a null byte');
  }

  final attachment = draft.attachment;
  if (attachment == null) return;
  if (!attachment.path.startsWith('/')) {
    throw const MailException(
      'invalidDraft',
      'Attachment path must be absolute',
    );
  }
  if (!_validMimeType.hasMatch(attachment.mimeType)) {
    throw const MailException(
      'invalidDraft',
      'Attachment MIME type is invalid',
    );
  }
}

bool _containsNull(String value) => value.contains('\u0000');

final _validMimeType = RegExp(r"^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$");
