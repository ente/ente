import Head from "next/head";
import React from "react";
import { isCustomAPIOrigin } from "../origins";

interface CustomHeadProps {
    title: string;
    viewportContent?: string;
}

const AlbumsFontPreloads: React.FC = () => (
    <>
        <link
            rel="preload"
            href="/fonts/inter-latin-wght-normal.woff2"
            as="font"
            type="font/woff2"
            crossOrigin="anonymous"
        />
    </>
);

/**
 * A custom version of "next/head" that sets the title, description, favicon and
 * some other boilerplate <head> tags.
 *
 * This assumes the existence of `public/images/favicon.png`.
 */
export const CustomHead: React.FC<React.PropsWithChildren<CustomHeadProps>> = ({
    title,
    children,
    viewportContent = "width=device-width, initial-scale=1",
}) => (
    <Head>
        {children}
        <title>{title}</title>
        <link rel="icon" href="/images/favicon.png" type="image/png" />
        <meta
            name="description"
            content="Ente - end-to-end encrypted cloud with open-source apps"
        />
        <meta name="viewport" content={viewportContent} />
        <meta name="referrer" content="strict-origin-when-cross-origin" />
    </Head>
);

/**
 * A static SSR-ed variant of {@link CustomHead} for use with the albums app
 * deployed on production Ente instances for link previews.
 *
 * In particular,
 *
 * - Any client side modifications to the document's head will be too late for
 *   use by the link previews, so the contents of this need to part of the
 *   static HTML.
 *
 * - "og:image" needs to be an absolute URL.
 *
 * To avoid getting in the way of self hosters, only inline this into builds
 * that use Ente's production API.
 */
export const CustomHeadAlbumsStatic: React.FC = () => (
    <Head>
        <AlbumsFontPreloads />
        <title>Ente Photos</title>
        <link rel="icon" href="/images/favicon.png" type="image/png" />
        <meta
            name="description"
            content="Safely store and share your best moments"
        />
        <meta
            property="og:image"
            content="https://albums.ente.com/images/preview.jpg"
        />
        {/* Twitter wants its own thing. */}
        <meta
            name="twitter:image"
            content="https://albums.ente.com/images/preview.jpg"
        />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="referrer" content="strict-origin-when-cross-origin" />
    </Head>
);

/**
 * A convenience fan out to conditionally show one of {@link CustomHead} or
 * {@link CustomHeadAlbumsStatic}.
 *
 * Use static production preview tags only when using Ente's production API.
 * Custom API builds should not inline production preview metadata into the
 * static HTML.
 */
export const CustomHeadAlbums: React.FC<CustomHeadProps> = ({ title }) =>
    isCustomAPIOrigin ? (
        <CustomHead {...{ title }}>
            <AlbumsFontPreloads />
        </CustomHead>
    ) : (
        <CustomHeadAlbumsStatic />
    );

/**
 * A static SSR-ed variant of {@link CustomHead} for use with the share app
 * (Public Locker) deployed on production Ente instances for link previews.
 *
 * Similar to {@link CustomHeadAlbumsStatic}, this includes Open Graph meta tags
 * with absolute URLs for social media preview images.
 */
export const CustomHeadShareStatic: React.FC = () => (
    <Head>
        <title>Ente Locker</title>
        <link rel="icon" href="/images/favicon.png" type="image/png" />
        <meta
            name="description"
            content="Securely store and share your documents"
        />
        <meta
            property="og:image"
            content="https://share.ente.com/images/preview.png"
        />
        <meta
            name="twitter:image"
            content="https://share.ente.com/images/preview.png"
        />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="referrer" content="strict-origin-when-cross-origin" />
    </Head>
);

/**
 * A convenience fan out to conditionally show one of {@link CustomHead} or
 * {@link CustomHeadShareStatic}.
 *
 * Use static production preview tags only when using Ente's production API.
 * Custom API builds should not inline production preview metadata into the
 * static HTML.
 */
export const CustomHeadShare: React.FC<CustomHeadProps> = ({ title }) =>
    isCustomAPIOrigin ? (
        <CustomHead {...{ title }} />
    ) : (
        <CustomHeadShareStatic />
    );
