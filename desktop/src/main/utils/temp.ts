import { app } from "electron/main";
import { existsSync } from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";
import type { ZipItem } from "../../types/ipc";
import log from "../log";
import { markClosableZip, openZip } from "../services/zip";
import { writeStream } from "./stream";

const enteTempDirPath = async () => {
    const result = path.join(app.getPath("temp"), "ente");
    await fs.mkdir(result, { recursive: true });
    return result;
};

const randomPrefix = () => {
    const ch = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    const randomChar = () => ch[Math.floor(Math.random() * ch.length)]!;

    return Array(10).fill("").map(randomChar).join("");
};

const isValidExtension = (extension: string) =>
    /^[a-z0-9]{1,244}$/i.test(extension);

export const imageInputExtension = (
    detectedExtension: string | undefined,
    fileName: string,
) => {
    const fileNameExtension = path.extname(fileName).slice(1);
    const mayBeTIFFBasedRAW = detectedExtension === "tif";
    return mayBeTIFFBasedRAW && isValidExtension(fileNameExtension)
        ? fileNameExtension
        : detectedExtension;
};

export const makeTempFilePath = async (extension?: string) => {
    if (extension && !isValidExtension(extension))
        throw new Error("Invalid temporary file extension");
    const tempDir = await enteTempDirPath();
    const suffix = extension ? "." + extension : "";
    let result: string;
    do {
        result = path.join(tempDir, randomPrefix() + suffix);
    } while (existsSync(result));
    return result;
};

export const deleteTempFile = async (tempFilePath: string) => {
    const tempDir = await enteTempDirPath();
    if (!tempFilePath.startsWith(tempDir))
        throw new Error(`Attempting to delete a non-temp file ${tempFilePath}`);
    await fs.rm(tempFilePath, { force: true });
};

export const deleteTempFileIgnoringErrors = async (tempFilePath: string) => {
    try {
        await deleteTempFile(tempFilePath);
    } catch (e) {
        log.error(`Could not delete temporary file at path ${tempFilePath}`, e);
    }
};

interface FileForStreamOrPathOrZipItem {
    path: string;
    isFileTemporary: boolean;
    writeToTemporaryFile: () => Promise<void>;
}

export const makeFileForStreamOrPathOrZipItem = async (
    item: ReadableStream | string | ZipItem,
    detectedExtension?: string,
): Promise<FileForStreamOrPathOrZipItem> => {
    let filePath: string;
    let isFileTemporary: boolean;
    let writeToTemporaryFile = async () => {
        /* no-op */
    };

    if (typeof item == "string") {
        filePath = item;
        isFileTemporary = false;
    } else {
        const extension = Array.isArray(item)
            ? imageInputExtension(detectedExtension, item[1])
            : detectedExtension;
        filePath = await makeTempFilePath(extension);
        isFileTemporary = true;
        if (item instanceof ReadableStream) {
            writeToTemporaryFile = () => writeStream(filePath, item);
        } else {
            writeToTemporaryFile = async () => {
                const [zipPath, entryName] = item;
                const zip = openZip(zipPath);
                try {
                    await zip.extract(entryName, filePath);
                } finally {
                    markClosableZip(zipPath);
                }
            };
        }
    }

    return { path: filePath, isFileTemporary, writeToTemporaryFile };
};
