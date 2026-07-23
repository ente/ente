class AccountDeletionSummary {
  const AccountDeletionSummary({
    required this.photosAndVideosCount,
    required this.authenticatorCodesCount,
    required this.lockerRecordsCount,
  });

  factory AccountDeletionSummary.fromJson(Map<String, dynamic> json) {
    return AccountDeletionSummary(
      photosAndVideosCount: _countFromJson(json['photosAndVideosCount']),
      authenticatorCodesCount: _countFromJson(json['authenticatorCodesCount']),
      lockerRecordsCount: _countFromJson(json['lockerRecordsCount']),
    );
  }

  final int photosAndVideosCount;
  final int authenticatorCodesCount;
  final int lockerRecordsCount;
}

int _countFromJson(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw const FormatException('Expected account deletion summary count');
}
