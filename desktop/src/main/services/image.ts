import fs from "node:fs/promises";
import path from "node:path";
import { type ZipItem } from "../../types/ipc";
import { execAsync, isDev } from "../utils/electron";
import {
    deleteTempFileIgnoringErrors,
    makeFileForStreamOrPathOrZipItem,
    makeTempFilePath,
} from "../utils/temp";

export const convertToJPEG = async (
    imageData: Uint8Array,
): Promise<Uint8Array<ArrayBuffer>> => {
    const inputFilePath = await makeTempFilePath();
    const outputFilePath = await makeTempFilePath("jpeg");

    const command = convertToJPEGCommand(inputFilePath, outputFilePath);

    try {
        await fs.writeFile(inputFilePath, imageData);
        await execAsync(command);
        return await fs.readFile(outputFilePath);
    } finally {
        await deleteTempFileIgnoringErrors(inputFilePath);
        await deleteTempFileIgnoringErrors(outputFilePath);
    }
};

const convertToJPEGCommand = (
    inputFilePath: string,
    outputFilePath: string,
) => {
    switch (process.platform) {
        case "darwin":
            return [
                "sips",
                "-s",
                "format",
                "jpeg",
                inputFilePath,
                "--out",
                outputFilePath,
            ];

        case "linux":
        case "win32":
            return [vipsPath(), "copy", inputFilePath, outputFilePath];

        default:
            throw new Error("Not available on the current OS/arch");
    }
};

const vipsPath = () =>
    path.join(
        isDev ? "build" : process.resourcesPath,
        process.platform == "win32" ? "vips.exe" : "vips",
    );

export const generateImageThumbnail = async (
    pathOrZipItem: string | ZipItem,
    maxDimension: number,
    maxSize: number,
): Promise<Uint8Array<ArrayBuffer>> => {
    const {
        path: inputFilePath,
        isFileTemporary: isInputFileTemporary,
        writeToTemporaryFile: writeToTemporaryInputFile,
    } = await makeFileForStreamOrPathOrZipItem(pathOrZipItem);

    const outputFilePath = await makeTempFilePath("jpeg");

    try {
        await writeToTemporaryInputFile();

        const shouldResize = await shouldResizeImage(
            inputFilePath,
            maxDimension,
        );
        let quality = 70;
        let command = generateImageThumbnailCommand(
            inputFilePath,
            outputFilePath,
            maxDimension,
            quality,
            shouldResize,
        );

        let thumbnail: Uint8Array<ArrayBuffer>;
        do {
            await execAsync(command);
            thumbnail = await fs.readFile(outputFilePath);
            quality -= 10;
            command = generateImageThumbnailCommand(
                inputFilePath,
                outputFilePath,
                maxDimension,
                quality,
                shouldResize,
            );
        } while (thumbnail.length > maxSize && quality > 50);
        return thumbnail;
    } finally {
        if (isInputFileTemporary)
            await deleteTempFileIgnoringErrors(inputFilePath);
        await deleteTempFileIgnoringErrors(outputFilePath);
    }
};

const generateImageThumbnailCommand = (
    inputFilePath: string,
    outputFilePath: string,
    maxDimension: number,
    quality: number,
    shouldResize: boolean,
) => {
    switch (process.platform) {
        case "darwin":
            return [
                "sips",
                "-s",
                "format",
                "jpeg",
                "-s",
                "formatOptions",
                `${quality}`,
                ...(shouldResize ? ["-Z", `${maxDimension}`] : []),
                inputFilePath,
                "--out",
                outputFilePath,
            ];

        case "linux":
        case "win32":
            return [
                vipsPath(),
                "thumbnail",
                inputFilePath,
                `${outputFilePath}[Q=${quality}]`,
                `${maxDimension}`,
                "--size",
                "down",
            ];

        default:
            throw new Error("Not available on the current OS/arch");
    }
};

const shouldResizeImage = async (
    inputFilePath: string,
    maxDimension: number,
) => {
    if (process.platform != "darwin") return true;

    const { stdout } = await execAsync([
        "sips",
        "-g",
        "pixelWidth",
        "-g",
        "pixelHeight",
        inputFilePath,
    ]);
    const width = parseSipsDimension(stdout, "pixelWidth");
    const height = parseSipsDimension(stdout, "pixelHeight");
    return Math.max(width, height) > maxDimension;
};

const parseSipsDimension = (output: string, property: string) => {
    const match = new RegExp(`^\\s*${property}:\\s*(\\d+)\\s*$`, "m").exec(
        output,
    );
    const dimension = match?.[1] ? Number.parseInt(match[1], 10) : 0;
    if (dimension <= 0)
        throw new Error(`Could not read ${property} from sips output`);
    return dimension;
};
