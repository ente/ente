import log from "ente-base/log";
import { preload } from "react-dom";

const prepareLikeAnimation = async () => {
    const wasmURL = new URL("@rive-app/canvas-lite/rive.wasm", import.meta.url)
        .href;
    preload(wasmURL, {
        as: "fetch",
        crossOrigin: "anonymous",
        fetchPriority: "low",
    });
    const [runtime, buffer] = await Promise.all([
        import("@rive-app/canvas-lite").then(async (runtime) => {
            runtime.RuntimeLoader.setWasmUrl(wasmURL);
            runtime.RuntimeLoader.setWasmFallbackUrl(null);
            await runtime.RuntimeLoader.awaitInstance();
            return runtime;
        }),
        fetch(new URL("../assets/like.riv", import.meta.url)).then(
            (response) => {
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                return response.arrayBuffer();
            },
        ),
    ]);
    const file = new runtime.RiveFile({ buffer, enableRiveAssetCDN: false });
    await file.init();
    file.getInstance();
    return { runtime, file };
};

let likeAnimation:
    | Promise<Awaited<ReturnType<typeof prepareLikeAnimation>> | undefined>
    | undefined;

export const preloadPostLikeAnimation = () => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches)
        return Promise.resolve(undefined);
    likeAnimation ??= prepareLikeAnimation().catch((error: unknown) => {
        likeAnimation = undefined;
        log.warn("Failed to prepare the like animation", error);
        return undefined;
    });
    return likeAnimation;
};
