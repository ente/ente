declare const cast: typeof import("../types/chromecast-sender").cast;
declare const chrome: typeof import("../types/chromecast-sender").chrome;

export const loadCast = (() => {
    let promise: Promise<typeof cast> | undefined;

    return () => {
        if (promise === undefined) {
            promise = new Promise((resolve) => {
                const script = document.createElement("script");
                script.src =
                    "https://www.gstatic.com/cv/js/sender/v1/cast_sender.js?loadCastFramework=1";
                window.__onGCastApiAvailable = (isAvailable) => {
                    if (isAvailable) {
                        cast.framework.CastContext.getInstance().setOptions({
                            receiverApplicationId: "F5BCEC64",
                            autoJoinPolicy:
                                chrome.cast.AutoJoinPolicy.ORIGIN_SCOPED,
                        });

                        resolve(cast);
                    }
                };
                document.body.appendChild(script);
            });
        }
        return promise;
    };
})();
