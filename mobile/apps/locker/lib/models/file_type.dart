enum FileType { image, video, livePhoto, other, info }

int getInt(FileType fileType) {
  switch (fileType) {
    case FileType.image:
      return 0;
    case FileType.video:
      return 1;
    case FileType.livePhoto:
      return 2;
    case FileType.other:
      return 3;
    case FileType.info:
      return 4;
  }
}

FileType getFileType(int fileType) {
  switch (fileType) {
    case 0:
      return FileType.image;
    case 1:
      return FileType.video;
    case 2:
      return FileType.livePhoto;
    case 3:
      return FileType.other;
    case 4:
      return FileType.info;
    default:
      return FileType.other;
  }
}

String getHumanReadableString(FileType fileType) {
  switch (fileType) {
    case FileType.image:
      return 'Images';
    case FileType.video:
      return 'Videos';
    case FileType.livePhoto:
      return 'Live Photos';
    case FileType.other:
      return 'Other Files';
    case FileType.info:
      return 'Information';
  }
}
