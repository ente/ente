const { Arch } = require("builder-util");
const { ensureFFmpeg } = require("./ffmpeg");
const { ensureVips } = require("./vips");

module.exports = async (context) => {
    await ensureVips(
        context.electronPlatformName,
        Arch[context.arch],
        context.packager.info.appDir,
    );
    await ensureFFmpeg(
        context.electronPlatformName,
        Arch[context.arch],
        context.packager.info.appDir,
    );
};
