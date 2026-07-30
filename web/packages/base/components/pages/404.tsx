import { useRouter } from "next/router";
import React, { useEffect } from "react";

/**
 * A reusable 404 page.
 */
const Page: React.FC = () => {
    // [Note: 404 back to home]
    //
    // In the desktop app, if the user presses the refresh button when the URL
    // has an attached query parameter, e.g. "/gallery?collectionId=xxx", then
    // the code in next-electron-server blindly appends the html extension to
    // this URL, resulting in it trying to open "gallery?collectionId=xxx.html"
    // instead of "gallery.html". It doesn't find such a file, causing it open
    // "404.html" (the static file generated from this file).
    //
    // One way around is to patch the package, e.g.
    // https://github.com/ente/next-electron-server/pull/1/files
    //
    // However, redirecting back to the root is arguably a better fallback in
    // all cases (even when running on our website), since our app is a SPA.

    const router = useRouter();

    useEffect(() => {
        void router.push("/");
    }, [router]);

    return <></>;
};

export default Page;
