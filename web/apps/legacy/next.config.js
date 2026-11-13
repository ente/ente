const crypto = require("crypto");
const fs = require("fs");

const baseConfig = require("ente-base/next.config.base.js");
const pdfWorkerPath =
    require.resolve("pdfjs-dist/legacy/build/pdf.worker.min.mjs");
const pdfWorkerSource = fs.readFileSync(pdfWorkerPath);
const pdfWorkerHash = crypto
    .createHash("sha256")
    .update(pdfWorkerSource)
    .digest("hex")
    .slice(0, 8);
const pdfWorkerAssetName = `static/media/pdf.worker.min.${pdfWorkerHash}.mjs`;

class EmitPDFWorkerPlugin {
    apply(compiler) {
        compiler.hooks.thisCompilation.tap(
            "EmitPDFWorkerPlugin",
            (compilation) => {
                compilation.hooks.processAssets.tap(
                    {
                        name: "EmitPDFWorkerPlugin",
                        stage: compiler.webpack.Compilation
                            .PROCESS_ASSETS_STAGE_ADDITIONAL,
                    },
                    () => {
                        compilation.emitAsset(
                            pdfWorkerAssetName,
                            new compiler.webpack.sources.RawSource(
                                pdfWorkerSource,
                            ),
                        );
                    },
                );
            },
        );
    }
}

module.exports = {
    ...baseConfig,
    env: {
        ...(baseConfig.env ?? {}),
        pdfWorkerSrc: `/_next/${pdfWorkerAssetName}`,
    },
    transpilePackages: [...(baseConfig.transpilePackages ?? []), "pdfjs-dist"],
    webpack: (config, options) => {
        const configured = baseConfig.webpack
            ? baseConfig.webpack(config, options)
            : config;
        if (!options.isServer) {
            configured.plugins.push(new EmitPDFWorkerPlugin());
        }
        return configured;
    },
};
