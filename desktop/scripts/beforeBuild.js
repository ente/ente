const fsp = require("fs/promises");

/**
 * This hook is invoked during the initial build (e.g. when triggered by
 * "npm run build"), and importantly, on each rebuild for a different
 * architecture during the build. We use it to ensure the vips binary matches
 * the current architecture. See "[Note: vips]" for more details.
 *
 * The documentation for this hook is at:
 * https://www.electron.build/app-builder-lib.interface.configuration#beforebuild
 *
 * > The function to be run before dependencies are installed or rebuilt.
 *
 * Here is an example of the context that it gets
 * https://www.electron.build/app-builder-lib.interface.beforebuildcontext
 *
 *     appDir: '/path/to/ente/desktop',
 *     platform: Platform {
 *         name: 'mac',
 *         buildConfigurationKey: 'mac',
 *         nodeName: 'darwin'
 *     },
 *     arch: 'arm64'
 *
 *  Note that we must not return falsey from this function, because:
 *
 *  > Resolving to false will skip dependencies install or rebuild.
 *
 */
module.exports = async (context) => {
    const { appDir, platform, arch } = context;

    // The arch used by Electron Builder is not the same as the arch used by
    // Node's process, but for the two cases that we care about, "x64" and
    // "arm64", both of them use the string constant and thus can be compared.
    //
    // https://github.com/electron-userland/electron-builder/blob/master/packages/builder-util/src/arch.ts#L9
    // https://nodejs.org/api/process.html#processarch
    if (arch == process.arch) {
        // `vips.js` would've already downloaded the file, nothing to do.
        return true;
    }

    const download = async (downloadName, outputName) => {
        const out = `${appDir}/build/${outputName}`;
        console.log(`Downloading ${downloadName}`);
        const downloadPath = `https://github.com/ente/libvips-packaging/releases/download/v8.16.0/${downloadName}`;
        return fetch(downloadPath)
            .then((res) => res.blob())
            .then((blob) => fsp.writeFile(out, blob.stream()))
            .then(() => fsp.chmod(out, "744"));
    };

    switch (`${platform.nodeName}-${arch}`) {
        case "linux-x64":
            await download("vips-x64", "vips");
        case "linux-arm64":
            await download("vips-arm64", "vips");
        case "win32-x64":
            await download("vips-x86_64.exe", "vips.exe");
        case "linux-arm64":
            await download("vips-aarch64.exe", "vips.exe");
    }

    return true;
};
