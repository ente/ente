const fsp = require("fs/promises");
const { stageNapiAddons } = require("./napi");
const { stageONNXRuntime } = require("./ort");

// Electron Builder skips its dependency rebuild after any falsy return.
module.exports = async (context) => {
    const { appDir, platform, arch } = context;

    await stageONNXRuntime(platform.nodeName, arch, appDir);
    await stageNapiAddons(appDir, platform.nodeName, arch);

    // The arch used by Electron Builder is not the same as the arch used by
    // Node's process, but for the two cases that we care about, "x64" and
    // "arm64", both of them use the string constant and thus can be compared.
    if (arch == process.arch) {
        // `vips.js` would've already downloaded the file, nothing to do.
        return true;
    }

    const download = async (downloadName, outputName) => {
        const out = `${appDir}/build/${outputName}`;
        console.log(`Downloading ${downloadName}`);
        const downloadPath = `https://github.com/ente/libvips-packaging/releases/download/v8.18.7/${downloadName}`;
        return fetch(downloadPath)
            .then((res) => res.blob())
            .then((blob) => fsp.writeFile(out, blob.stream()))
            .then(() => fsp.chmod(out, "744"));
    };

    switch (`${platform.nodeName}-${arch}`) {
        case "linux-x64":
            await download("vips-x64", "vips");
            break;
        case "linux-arm64":
            await download("vips-arm64", "vips");
            break;
        case "win32-x64":
            await download("vips-x86_64.exe", "vips.exe");
            break;
        case "win32-arm64":
            await download("vips-aarch64.exe", "vips.exe");
    }

    return true;
};
