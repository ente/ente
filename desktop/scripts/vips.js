const fs = require("fs");
const fsp = require("fs/promises");

const main = () => {
    // macOS uses sips
    switch (`${process.platform}-${process.arch}`) {
        case "linux-x64":
            return downloadIfNeeded("vips-x64", "vips");
        case "linux-arm64":
            return downloadIfNeeded("vips-arm64", "vips");
        case "win32-x64":
            return downloadIfNeeded("vips-x86_64.exe", "vips.exe");
        case "win32-arm64":
            return downloadIfNeeded("vips-aarch64.exe", "vips.exe");
    }
};

const downloadIfNeeded = (downloadName, outputName) => {
    const out = `build/${outputName}`;

    try {
        // chmod is the final download step, so executable means complete.
        fs.accessSync(out, fs.constants.X_OK);
        return;
    } catch {}

    console.log(`Downloading ${downloadName}`);
    const downloadPath = `https://github.com/ente/libvips-packaging/releases/download/v8.18.7/${downloadName}`;
    return fetch(downloadPath)
        .then((res) => res.blob())
        .then((blob) => fsp.writeFile(out, blob.stream()))
        .then(() => fsp.chmod(out, "744"));
};

main();
