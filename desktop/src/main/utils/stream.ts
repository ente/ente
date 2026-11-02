import { createWriteStream, existsSync } from "node:fs";
import fs from "node:fs/promises";
import { Readable } from "node:stream";

export const writeStream = (
    filePath: string,
    readableStream: unknown, // @ts-expect-error Node and web ReadableStream types disagree.
) => writeNodeStream(filePath, Readable.fromWeb(readableStream));

export const writeNodeStream = async (
    filePath: string,
    fileStream: NodeJS.ReadableStream,
) => {
    const writeable = createWriteStream(filePath, { mode: 0o600 });

    fileStream.on("error", (err: Error) => {
        writeable.destroy(err);
    });

    fileStream.pipe(writeable);

    await new Promise<void>((resolve, reject) => {
        writeable.on("finish", resolve);
        writeable.on("error", (err) => {
            if (existsSync(filePath)) {
                void fs.unlink(filePath);
            }
            reject(err);
        });
    });
};
