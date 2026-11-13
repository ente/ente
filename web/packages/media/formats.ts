// Image extensions that the browser is unlikely to be able to render, but
// which our desktop app should be able to convert to JPEG. Both conditions
// must hold for an extension to be in this list.
const needsJPEGConversionExtensions = [
    "arw",
    "cr2",
    "cr3",
    "dng",
    "heic",
    "jp2",
    "nef",
    "nrw",
    "orf",
    "pef",
    "psd",
    "raf",
    "rw2",
    "srw",
    "tif",
    "tiff",
];

export const needsJPEGConversion = (extension: string) =>
    needsJPEGConversionExtensions.includes(extension.toLowerCase());

export const isHEICExtension = (extension: string) => {
    const ext = extension.toLowerCase();
    return ext == "heic" || ext == "heif";
};
