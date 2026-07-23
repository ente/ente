/**
 * @file A bridge to the ffmpeg utility process. This code runs in the main
 * process.
 */

import { wrap } from "comlink";
import fs from "node:fs/promises";
import type { FFmpegCommand, ZipItem } from "../../types/ipc";
import {
    deleteTempFileIgnoringErrors,
    makeFileForStreamOrPathOrZipItem,
    makeTempFilePath,
} from "../utils/temp";
import type { FFmpegUtilityProcess } from "./ffmpeg-worker";
import { ffmpegUtilityProcessEndpoint } from "./workers";

/**
 * Return a handle to the ffmpeg utility process, starting it if needed.
 */
export const ffmpegUtilityProcess = () =>
    ffmpegUtilityProcessEndpoint().then((port) =>
        wrap<FFmpegUtilityProcess>(port),
    );

/**
 * Implement the IPC "ffmpegExec" contract, writing the input and output to
 * temporary files as needed, and then forward to the {@link ffmpegExec} running
 * in the utility process.
 */
export const ffmpegExec = async (
    command: FFmpegCommand,
    pathOrZipItem: string | ZipItem,
    outputFileExtension: string,
): Promise<Uint8Array<ArrayBuffer>> =>
    withInputFile(pathOrZipItem, async (worker, inputFilePath) => {
        const outputFilePath = await makeTempFilePath(outputFileExtension);
        try {
            await worker.ffmpegExec(command, inputFilePath, outputFilePath);
            return await fs.readFile(outputFilePath);
        } finally {
            await deleteTempFileIgnoringErrors(outputFilePath);
        }
    });

export const withInputFile = async <T>(
    pathOrZipItem: string | ZipItem,
    f: (worker: FFmpegUtilityProcess, inputFilePath: string) => Promise<T>,
): Promise<T> => {
    const worker = await ffmpegUtilityProcess();

    const {
        path: inputFilePath,
        isFileTemporary: isInputFileTemporary,
        writeToTemporaryFile: writeToTemporaryInputFile,
    } = await makeFileForStreamOrPathOrZipItem(pathOrZipItem);

    try {
        await writeToTemporaryInputFile();

        return await f(worker, inputFilePath);
    } finally {
        if (isInputFileTemporary)
            await deleteTempFileIgnoringErrors(inputFilePath);
    }
};

/**
 * Implement the IPC "ffmpegDetermineVideoDuration" contract, writing the input
 * to temporary files as needed, and then forward to the
 * {@link ffmpegDetermineVideoDuration} running in the utility process.
 */
export const ffmpegDetermineVideoDuration = async (
    pathOrZipItem: string | ZipItem,
): Promise<number> =>
    withInputFile(pathOrZipItem, async (worker, inputFilePath) =>
        worker.ffmpegDetermineVideoDuration(inputFilePath),
    );
