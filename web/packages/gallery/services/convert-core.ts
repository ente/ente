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

/**
 * Return a new {@link Blob} containing an image's data in a format that the
 * browser likely knows how to render in an img tag or on a canvas.
 *
 * The type of the returned blob is set, whenever possible, to the MIME type of
 * the data that we're dealing with.
 *
 * The logic used by this function is:
 *
 * 1. Try to detect the MIME type of the file from its contents and/or name.
 *
 * 2. If this detected type is one of the types that we know that the browser
 *    likely cannot render, continue. Otherwise return the imageBlob that was
 *    passed in after setting its MIME type.
 *
 * 3. If the caller provides a native JPEG converter, try that first and return
 *    the resultant JPEG blob.
 *
 * 4. If this is an HEIC file and the browser does not have native HEIC support,
 *    then use our Wasm HEIC converter and return the resultant JPEG blob.
 *
 * 5. Otherwise return the original with the MIME type if we were able to deduce
 *    one.
 *
 * It will catch all errors and return the original in those cases.
 */
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
                // If the browser already knows how to natively render HEICs,
                // e.g. Safari 17+, Wasm conversion is unnecessary and slower.
                if (mimeType == "image/heic" && (await isHEICSupported())) {
                    log.debug(
                        () => `Using native HEIC support for ${fileName}`,
                    );
                } else {
                    return await heicToJPEG(imageBlob);
                }
            }
        }

        // Either it is something that the browser already knows how to render
        // (e.g. JPEG/PNG), or is a file extension that might be supported in
        // some browsers (e.g. JPEG 2000), or a file extension that we haven't
        // specifically whitelisted for conversion.
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

/**
 * Return true if the browser can natively render HEIC files.
 *
 * For performance, the result of the check is cached. There shouldn't be a
 * reason for this cache to need be invalidated, the browser shouldn't suddenly
 * drop its HEIC support in the middle of it running.
 *
 * The check works by trying to load a small HEIC file. Currently, the only
 * browser with support for HEIC is Safari.
 */
export const isHEICSupported = () =>
    (_isHEICSupported ??= new Promise((resolve) => {
        const image = new Image();
        image.onload = () => resolve(true);
        image.onerror = () => resolve(false);
        image.src = testHEICDataURL;
    }));

/**
 * A data URL encoding the smallest HEIC image (439 bytes).
 *
 * Source:
 * https://github.com/vvideo/detect-audio-video/blob/main/src/image/smallest/index.ts
 */
const testHEICDataURL =
    "data:image/heic;base64,AAAAGGZ0eXBoZWljAAAAAG1pZjFoZWljAAABaW1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAHBpY3QAAAAAAAAAAAAAAAAAAAAADnBpdG0AAAAAAAEAAAAiaWxvYwAAAABEQAABAAEAAAAAAYkAAQAAAAAAAAAuAAAAI2lpbmYAAAAAAAEAAAAVaW5mZQIAAAAAAQAAaHZjMQAAAADpaXBycAAAAMppcGNvAAAAdmh2Y0MBA3AAAAAAAAAAAAAe8AD8/fj4AAAPAyAAAQAYQAEMAf//A3AAAAMAkAAAAwAAAwAeugJAIQABACpCAQEDcAAAAwCQAAADAAADAB6gIIEFluqumubgIaDAgAAAAwCAAAADAIQiAAEABkQBwXPBiQAAABRpc3BlAAAAAAAAAEAAAABAAAAAKGNsYXAAAAABAAAAAQAAAAEAAAAB////wQAAAAL////BAAAAAgAAABBwaXhpAAAAAAMICAgAAAAXaXBtYQAAAAAAAAABAAEEgQKDBAAAADZtZGF0AAAAKigBrwayEx2gkim3i/2Rd0CR/V6h6GbEyV3dheegYfLV9ZwraCH8nff+7w==";

export interface PlayableVideoURLWebOpts {
    convertToMP4: ConvertToMP4;
    shouldConvertPlayableVideo?: () => boolean;
    shouldConvertUnplayableVideo?: (videoBlob: Blob) => boolean;
}

/**
 * Return an object URL containing a video's data in a format that the browser
 * likely knows how to play back using a video tag.
 *
 * Unlike {@link renderableImageBlobWeb}, this uses a simpler flowchart:
 *
 * 1. If the browser thinks it can play the video, return an object URL created
 *    directly from the provided {@link videoBlob}, unless the caller asks to
 *    force a conversion for a known platform quirk.
 *
 * 2. Otherwise try to convert using FFmpeg if the caller allows it.
 *
 * 3. On errors, return the original object URL as would've happened for step 1.
 */
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
            return URL.createObjectURL(
                new Blob([convertedBlob], { type: "video/mp4" }),
            );
        } catch (e) {
            log.error(`Video conversion failed for ${videoFileName}`, e);
        }
    }

    return videoObjectURL;
};

const shouldConvertSmallVideo = (videoBlob: Blob) =>
    videoBlob.size < 100 * 1024 * 1024; /* 100 MB, arbitrary */

const videoBlobWithSafariMIME = async (
    videoFileName: string,
    videoBlob: Blob,
) => {
    // Safari-only MIME correction for blob URLs to avoid NotSupportedError.
    // Prefer extension-based lookup first (fast, no sniff). Fallback to
    // content detection only if extension is unknown.
    //
    // We use isHEICSupported() as a Safari proxy. Currently, Safari is the only
    // browser with native HEIC support, so gating here effectively targets
    // Safari engines where stricter blob MIME handling applies.
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

/**
 * Try to see if the browser thinks it can play the video pointed to by the
 * given {@link url} by creating a video element and initiating playback.
 *
 * Note that this can sometimes cause false positives if the browser can play
 * some of the streams in the video, but not all. For example, the browser may
 * be able to play back the video stream, but not the audio stream; in such
 * cases this function will return true, causing us to skip conversion, but when
 * the user actually plays the video there will be no sound.
 *
 * To deal with such cases in a holistic manner, we have a streaming variant of
 * the video that gets transcoded into a near universal format.
 */
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
