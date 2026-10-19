export const FileType = { image: 0, video: 1, livePhoto: 2 } as const;

export type FileType = (typeof FileType)[keyof typeof FileType];

export interface FileTypeInfo {
    fileType: FileType;
    extension: string;
    mimeType?: string;
}

// These are formats that automatic file type detection misses for some files
// found in the wild.
export const KnownFileTypeInfos: FileTypeInfo[] = [
    { fileType: FileType.image, extension: "jpeg", mimeType: "image/jpeg" },
    { fileType: FileType.image, extension: "jpg", mimeType: "image/jpeg" },
    { fileType: FileType.video, extension: "webm", mimeType: "video/webm" },
    { fileType: FileType.video, extension: "mod", mimeType: "video/mpeg" },
    { fileType: FileType.video, extension: "mp4", mimeType: "video/mp4" },
    { fileType: FileType.image, extension: "gif", mimeType: "image/gif" },
    { fileType: FileType.video, extension: "dv", mimeType: "video/x-dv" },
    { fileType: FileType.video, extension: "wmv", mimeType: "video/x-ms-asf" },
    { fileType: FileType.video, extension: "hevc", mimeType: "video/hevc" },
    {
        fileType: FileType.image,
        extension: "raf",
        mimeType: "image/x-fuji-raf",
    },
    {
        fileType: FileType.image,
        extension: "orf",
        mimeType: "image/x-olympus-orf",
    },
    {
        fileType: FileType.image,
        extension: "crw",
        mimeType: "image/x-canon-crw",
    },
    {
        fileType: FileType.image,
        extension: "nrw",
        mimeType: "image/x-nikon-nrw",
    },
    {
        fileType: FileType.image,
        extension: "pef",
        mimeType: "image/x-pentax-pef",
    },
    {
        fileType: FileType.image,
        extension: "srw",
        mimeType: "image/x-samsung-srw",
    },
    { fileType: FileType.video, extension: "mov", mimeType: "video/quicktime" },
];

export const KnownNonMediaFileExtensions = ["xmp", "html", "txt"];
