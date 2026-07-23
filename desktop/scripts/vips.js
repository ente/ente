/**
 * [Note: vips]
 *
 * For use within our Electron app we need static builds for Linux and Windows
 * for both x64 and ARM. For this, we need a custom workflow because (as of
 * writing) upstream doesn't publish these.
 *
 * This is our custom workflow, which runs on a fork of upstream:
 * https://github.com/ente/libvips-packaging/commit/a298aff3e1f25f713508d31d0c3a55a4f828fdd3
 *
 * The binaries it creates are available at
 * https://github.com/ente/libvips-packaging/releases/tag/v8.16.0
 *
 * To integrate this binary, we need to modify two places:
 *
 * 1. This script, `vips.js`, runs during "npm install" (it is set as the
 *    "prepare" step in our `package.json`). It downloads the relevant binary
 *    for the current OS/arch combination and places it in the `build` folder,
 *    allowing it to be used during development.
 *
 * 2. The sibling script, `beforeBuild.js`, runs during "npm run build" (it is set
 *    as the beforeBuild script in `electrons-builder.yml`). It downloads the
 *    relevant binary for the OS/arch combination being built.
 *
 * Note that `vips.js` would've already run once `beforeBuild.js` is run, but on
 * our CI we prepare builds for multiple architectures in one go, so we need to
 * unconditionally replace the binary with the relevant one for the current
 * architecture being built (which might be different from the one we're running
 * on). `beforeBuild.js` runs for each architecture being built.
 *
 * On macOS, we don't need `vips` since there we use the native `sips`.
 */

const fs = require("fs");
const fsp = require("fs/promises");

const main = () => {
    switch (`${process.platform}-${process.arch}`) {
        case "linux-x64":
            return downloadIfNeeded("vips-x64", "vips");
        case "linux-arm64":
            return downloadIfNeeded("vips-arm64", "vips");
        case "win32-x64":
            return downloadIfNeeded("vips-x86_64.exe", "vips.exe");
        case "linux-arm64":
            return downloadIfNeeded("vips-aarch64.exe", "vips.exe");
    }
};

const downloadIfNeeded = (downloadName, outputName) => {
    const out = `build/${outputName}`;

    try {
        // Making the file executable is the last step, so if the file exists at
        // this path and is executable, we assume it is the correct one.
        fs.accessSync(out, fs.constants.X_OK);
        return;
    } catch {}

    console.log(`Downloading ${downloadName}`);
    const downloadPath = `https://github.com/ente/libvips-packaging/releases/download/v8.16.0/${downloadName}`;
    return fetch(downloadPath)
        .then((res) => res.blob())
        .then((blob) => fsp.writeFile(out, blob.stream()))
        .then(() => fsp.chmod(out, "744"));
};

main();
