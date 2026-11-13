const { stageNapiAddons } = require("./napi");
const { stageONNXRuntime } = require("./ort");

// Electron Builder skips its dependency rebuild after any falsy return.
module.exports = async (context) => {
    const { appDir, platform, arch } = context;

    await stageONNXRuntime(platform.nodeName, arch, appDir);
    await stageNapiAddons(appDir, platform.nodeName, arch);

    return true;
};
