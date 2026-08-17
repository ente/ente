enum UploadStrategy { ifMissing, always, other }

int getInt(UploadStrategy uploadType) {
  switch (uploadType) {
    case UploadStrategy.ifMissing:
      return 0;
    case UploadStrategy.always:
      return 1;
    default:
      return -1;
  }
}

UploadStrategy getUploadType(int uploadType) {
  switch (uploadType) {
    case 0:
      return UploadStrategy.ifMissing;
    case 1:
      return UploadStrategy.always;
    default:
      return UploadStrategy.other;
  }
}
