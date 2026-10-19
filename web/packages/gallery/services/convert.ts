import { isDesktop } from "ente-base/app";
import log from "ente-base/log";
import { workerBridge } from "ente-base/worker/worker-bridge";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { playableVideoURLWeb, renderableImageBlobWeb } from "./convert-core";
import { convertToMP4 } from "./ffmpeg";

export const renderableImageBlob = async (
    imageBlob: Blob,
    fileName: string,
): Promise<Blob> =>
    renderableImageBlobWeb(
        imageBlob,
        fileName,
        isDesktop
            ? {
                  convertToJPEG: nativeConvertToJPEG,
                  onConvertToJPEGError: (e) =>
                      log.error("Native conversion to JPEG failed", e),
              }
            : undefined,
    );

const nativeConvertToJPEG = async (
    imageBlob: Blob,
    detectedExtension: string,
    fileName: string,
) => {
    const startTime = Date.now();
    const imageData = new Uint8Array(await imageBlob.arrayBuffer());
    const electron = globalThis.electron;
    // Workers route through the main thread because they cannot access electron.
    const jpegData = electron
        ? await electron.convertToJPEG(imageData, detectedExtension, fileName)
        : await workerBridge!.convertToJPEG(
              imageData,
              detectedExtension,
              fileName,
          );
    log.debug(() => `Native JPEG conversion took ${Date.now() - startTime} ms`);
    return new Blob([jpegData], { type: "image/jpeg" });
};

export const playableVideoURL = async (
    file: EnteFile,
    videoFileName: string,
    videoBlob: Blob,
): Promise<string> =>
    playableVideoURLWeb(videoFileName, videoBlob, {
        convertToMP4,
        // isPlaybackPossible can return true when Chromium plays only the
        // audio stream. For live photos on Linux desktop, force conversion as a
        // pragmatic fallback; their video component is short.
        shouldConvertPlayableVideo: () =>
            isDesktop &&
            file.metadata.fileType == FileType.livePhoto &&
            navigator.platform.startsWith("Linux"),
        shouldConvertUnplayableVideo: (videoBlob) =>
            isDesktop || videoBlob.size < 100 * 1024 * 1024,
    });
