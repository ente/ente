enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  error,
  cancelled,
}

class DownloadTask {
  final int id;
  final String filename;
  final int totalBytes;
  final int createdAt;
  final int updatedAt;
  final String? sourceFileJson;
  int bytesDownloaded;
  DownloadStatus status;
  String? error;
  String? filePath;

  DownloadTask({
    required this.id,
    required this.filename,
    required this.totalBytes,
    int? createdAt,
    int? updatedAt,
    this.sourceFileJson,
    this.bytesDownloaded = 0,
    this.status = DownloadStatus.pending,
    this.error,
    this.filePath,
  }) : createdAt = createdAt ?? DateTime.now().microsecondsSinceEpoch,
       updatedAt = updatedAt ?? DateTime.now().microsecondsSinceEpoch;

  double get progress => totalBytes > 0 ? bytesDownloaded / totalBytes : 0.0;
  bool get isCompleted => status == DownloadStatus.completed;
  bool get isActive => status == DownloadStatus.downloading;
  bool get isFinished => [
    DownloadStatus.completed,
    DownloadStatus.error,
    DownloadStatus.cancelled,
  ].contains(status);

  Map<String, dynamic> toMap() => {
    'id': id,
    'filename': filename,
    'totalBytes': totalBytes,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'sourceFileJson': sourceFileJson,
    'bytesDownloaded': bytesDownloaded,
    'status': status.name,
    'error': error,
    'filePath': filePath,
  };

  static DownloadTask fromMap(Map<String, dynamic> map) => DownloadTask(
    id: map['id'],
    filename: map['filename'],
    totalBytes: map['totalBytes'],
    createdAt: map['createdAt'],
    updatedAt: map['updatedAt'],
    sourceFileJson: map['sourceFileJson'],
    bytesDownloaded: map['bytesDownloaded'] ?? 0,
    status: DownloadStatus.values.byName(map['status']),
    error: map['error'],
    filePath: map['filePath'],
  );

  DownloadTask copyWith({
    int? createdAt,
    int? updatedAt,
    String? sourceFileJson,
    int? bytesDownloaded,
    DownloadStatus? status,
    String? error,
    String? filePath,
  }) => DownloadTask(
    id: id,
    filename: filename,
    totalBytes: totalBytes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? DateTime.now().microsecondsSinceEpoch,
    sourceFileJson: sourceFileJson ?? this.sourceFileJson,
    bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
    status: status ?? this.status,
    error: error ?? this.error,
    filePath: filePath ?? this.filePath,
  );
}

class DownloadResult {
  final DownloadTask task;
  final bool success;

  DownloadResult(this.task, this.success);
}
