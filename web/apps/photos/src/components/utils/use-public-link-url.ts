import { appendCollectionKeyToShareURL } from "ente-gallery/services/share";
import type { Collection, PublicURL } from "ente-media/collection";
import { useEffect, useMemo, useState } from "react";

export const usePublicLinkURL = (
    collection: Pick<Collection, "id" | "key">,
    publicURL: PublicURL | undefined,
    customDomain?: string,
) => {
    const url = publicURL?.url;
    const { id, key } = collection;
    const input = useMemo(
        () => ({ id, key, url, customDomain }),
        [id, key, url, customDomain],
    );
    const [result, setResult] = useState<
        | { input: typeof input; resolvedURL?: string; error?: unknown }
        | undefined
    >();

    useEffect(() => {
        if (!input.url) return;
        let cancelled = false;

        void appendCollectionKeyToShareURL(input.url, input.key)
            .then((url) => {
                if (input.customDomain) {
                    const customURL = new URL(url);
                    customURL.host = input.customDomain;
                    url = customURL.href;
                }
                if (!cancelled) setResult({ input, resolvedURL: url });
            })
            .catch((error: unknown) => {
                if (!cancelled) setResult({ input, error });
            });

        return () => {
            cancelled = true;
        };
    }, [input]);

    const currentResult = result?.input === input ? result : undefined;
    return {
        resolvedURL: currentResult?.resolvedURL,
        isLoading: Boolean(url) && !currentResult,
        error: currentResult?.error,
    };
};
