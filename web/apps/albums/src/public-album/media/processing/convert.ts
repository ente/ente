import {
    playableVideoURLWeb,
    renderableImageBlobWeb,
} from "ente-gallery/services/convert-core";
import type { EnteFile } from "ente-media/file";

export const renderableImageBlob = async (
    imageBlob: Blob,
    fileName: string,
): Promise<Blob> => renderableImageBlobWeb(imageBlob, fileName);

export const playableVideoURL = async (
    _file: EnteFile,
    videoFileName: string,
    videoBlob: Blob,
): Promise<string> =>
    playableVideoURLWeb(videoFileName, videoBlob, {
        convertToMP4: async (blob) => {
            const ffmpeg = await import("ente-gallery/services/ffmpeg");
            return ffmpeg.convertToMP4(blob);
        },
    });
