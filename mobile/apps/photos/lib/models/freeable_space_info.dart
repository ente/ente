class FreeableSpaceInfo {
  final List<String> localIDs;
  final int size;

  FreeableSpaceInfo(this.localIDs, this.size);
}

class FreeableFileIDs {
  final List<String> localIDs;
  final List<int> uploadedIDs;
  // Approximate device size; the stored size is for the encrypted upload.
  final int localSize;

  FreeableFileIDs(this.localIDs, this.uploadedIDs, this.localSize);
}
