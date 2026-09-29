import { lowercaseExtension } from "ente-base/file-name";
import log from "ente-base/log";
import { KnownFileTypeInfos } from "ente-media/file-type";
import { isHEICExtension, needsJPEGConversion } from "ente-media/formats";
import { heicToJPEG } from "ente-media/heic-convert";
import { detectFileTypeInfo } from "../utils/detect-type";

type ConvertToMP4 = (blob: Blob) => Promise<Blob | Uint8Array<ArrayBuffer>>;

export interface RenderableImageBlobWebOpts {
    convertToJPEG?: (imageBlob: Blob) => Promise<Blob>;
    onConvertToJPEGError?: (e: unknown) => void;
}

export const renderableImageBlobWeb = async (
    imageBlob: Blob,
    fileName: string,
    opts?: RenderableImageBlobWebOpts,
): Promise<Blob> => {
    try {
        const file = new File([imageBlob], fileName);
        const fileTypeInfo = await detectFileTypeInfo(file);
        const { extension, mimeType } = fileTypeInfo;

        if (needsJPEGConversion(extension)) {
            log.debug(() => [`Converting ${fileName} to JPEG`, fileTypeInfo]);

            if (opts?.convertToJPEG) {
                try {
                    return await opts.convertToJPEG(imageBlob);
                } catch (e) {
                    opts.onConvertToJPEGError?.(e);
                }
            }

            if (isHEICExtension(extension)) {
                if (mimeType == "image/heic" && (await isHEICSupported())) {
                    log.debug(
                        () => `Using native HEIC support for ${fileName}`,
                    );
                } else {
                    return await heicToJPEG(imageBlob);
                }
            }
        }

        if (!mimeType) {
            log.info(
                "Attempting to convert a file without a MIME type",
                fileName,
            );
            return imageBlob;
        }

        return new Blob([imageBlob], { type: mimeType });
    } catch (e) {
        log.error(`Failed to convert ${fileName}, will use the original`, e);
        return imageBlob;
    }
};

let _isHEICSupported: Promise<boolean> | undefined;

const isHEICSupported = () =>
    (_isHEICSupported ??= new Promise((resolve) => {
        const image = new Image();
        image.onload = () => resolve(true);
        image.onerror = () => resolve(false);
        image.src = testHEICDataURL;
    }));

const testHEICDataURL =
    "data:image/heic;base64,AAAAGGZ0eXBoZWljAAAAAG1pZjFoZWljAAABaW1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAHBpY3QAAAAAAAAAAAAAAAAAAAAADnBpdG0AAAAAAAEAAAAiaWxvYwAAAABEQAABAAEAAAAAAYkAAQAAAAAAAAAuAAAAI2lpbmYAAAAAAAEAAAAVaW5mZQIAAAAAAQAAaHZjMQAAAADpaXBycAAAAMppcGNvAAAAdmh2Y0MBA3AAAAAAAAAAAAAe8AD8/fj4AAAPAyAAAQAYQAEMAf//A3AAAAMAkAAAAwAAAwAeugJAIQABACpCAQEDcAAAAwCQAAADAAADAB6gIIEFluqumubgIaDAgAAAAwCAAAADAIQiAAEABkQBwXPBiQAAABRpc3BlAAAAAAAAAEAAAABAAAAAKGNsYXAAAAABAAAAAQAAAAEAAAAB////wQAAAAL////BAAAAAgAAABBwaXhpAAAAAAMICAgAAAAXaXBtYQAAAAAAAAABAAEEgQKDBAAAADZtZGF0AAAAKigBrwayEx2gkim3i/2Rd0CR/V6h6GbEyV3dheegYfLV9ZwraCH8nff+7w==";

export interface PlayableVideoURLWebOpts {
    convertToMP4: ConvertToMP4;
    shouldConvertPlayableVideo?: () => boolean;
    shouldConvertUnplayableVideo?: (videoBlob: Blob) => boolean;
}

export const playableVideoURLWeb = async (
    videoFileName: string,
    videoBlob: Blob,
    {
        convertToMP4,
        shouldConvertPlayableVideo = () => false,
        shouldConvertUnplayableVideo = shouldConvertSmallVideo,
    }: PlayableVideoURLWebOpts,
): Promise<string> => {
    const typedBlob = await videoBlobWithSafariMIME(videoFileName, videoBlob);
    const videoObjectURL = URL.createObjectURL(typedBlob);
    const isPlayable = await isPlaybackPossible(videoObjectURL);
    const shouldConvert = isPlayable
        ? shouldConvertPlayableVideo()
        : shouldConvertUnplayableVideo(videoBlob);

    if (shouldConvert) {
        try {
            log.info(`Converting ${videoFileName} to mp4`);
            const convertedBlob = await convertToMP4(videoBlob);
            const convertedURL = URL.createObjectURL(
                new Blob([convertedBlob], { type: "video/mp4" }),
            );
            URL.revokeObjectURL(videoObjectURL);
            return convertedURL;
        } catch (e) {
            log.error(`Video conversion failed for ${videoFileName}`, e);
        }
    }

    return videoObjectURL;
};

// Arbitrary 100 MB guard against expensive Wasm conversion.
const shouldConvertSmallVideo = (videoBlob: Blob) =>
    videoBlob.size < 100 * 1024 * 1024;

const videoBlobWithSafariMIME = async (
    videoFileName: string,
    videoBlob: Blob,
) => {
    // Safari rejects blob URLs whose MIME type is missing or wrong.
    // HEIC support is used as a Safari proxy.
    if (!(await isHEICSupported())) return videoBlob;

    const ext = lowercaseExtension(videoFileName);
    const known = KnownFileTypeInfos.find((f) => f.extension === ext);
    const knownMIME = known?.mimeType;
    if (knownMIME && knownMIME !== videoBlob.type) {
        return new Blob([videoBlob], { type: knownMIME });
    }

    try {
        const detected = await detectFileTypeInfo(
            new File([videoBlob], videoFileName),
        );
        if (detected.mimeType && detected.mimeType !== videoBlob.type) {
            return new Blob([videoBlob], { type: detected.mimeType });
        }
    } catch {
        // Best-effort only; fall back to original blob on detection failure.
    }

    return videoBlob;
};

// canplay can succeed when only the video stream is supported.
const isPlaybackPossible = async (url: string): Promise<boolean> =>
    new Promise((resolve) => {
        const t = setTimeout(() => {
            video.remove();
            resolve(false);
        }, 1000);

        const video = document.createElement("video");
        video.addEventListener("canplay", () => {
            clearTimeout(t);
            video.remove();
            resolve(video.duration > 0);
        });
        video.addEventListener("error", () => {
            clearTimeout(t);
            video.remove();
            resolve(false);
        });

        video.src = url;
    });
