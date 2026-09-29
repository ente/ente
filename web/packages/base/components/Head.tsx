import Head from "next/head";
import React from "react";
import { isCustomAPIOrigin } from "../origins";

interface CustomHeadProps {
    title: string;
    description?: string;
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

const albumsPreviewTitle = "Photos, shared with you";
const albumsPreviewDescription = "Tap to view on Ente";
const albumsPreviewImage = "https://albums.ente.com/images/preview.png";
const photosPreviewDescription =
    "Store and share your photos with absolute privacy.";
const photosPreviewImage = "https://photos.ente.com/images/preview.png";

export const CustomHead: React.FC<React.PropsWithChildren<CustomHeadProps>> = ({
    title,
    children,
    description = "Ente - end-to-end encrypted cloud with open-source apps",
    viewportContent = "width=device-width, initial-scale=1",
}) => (
    <Head>
        {children}
        <title>{title}</title>
        <link rel="icon" href="/images/favicon.png" type="image/png" />
        <meta name="description" content={description} />
        <meta name="viewport" content={viewportContent} />
        <meta name="referrer" content="strict-origin-when-cross-origin" />
    </Head>
);

const CustomHeadPhotosStatic: React.FC<CustomHeadProps> = ({ title }) => (
    <CustomHead title={title} description={photosPreviewDescription}>
        <meta property="og:type" content="website" />
        <meta property="og:title" content={title} />
        <meta property="og:description" content={photosPreviewDescription} />
        <meta property="og:image" content={photosPreviewImage} />
        <meta property="og:image:type" content="image/png" />
        <meta property="og:image:width" content="1200" />
        <meta property="og:image:height" content="630" />
        <meta name="twitter:card" content="summary_large_image" />
        <meta name="twitter:title" content={title} />
        <meta name="twitter:description" content={photosPreviewDescription} />
        <meta name="twitter:image" content={photosPreviewImage} />
    </CustomHead>
);

export const CustomHeadPhotos: React.FC<CustomHeadProps> = ({ title }) =>
    isCustomAPIOrigin ? (
        <CustomHead {...{ title }} />
    ) : (
        <CustomHeadPhotosStatic {...{ title }} />
    );

// Link preview crawlers only see static HTML, and og:image must be absolute.
const CustomHeadAlbumsStatic: React.FC = () => (
    <Head>
        <AlbumsFontPreloads />
        <title>Ente Photos</title>
        <link rel="icon" href="/images/favicon.png" type="image/png" />
        <meta name="description" content={albumsPreviewDescription} />
        <meta property="og:type" content="website" />
        <meta property="og:title" content={albumsPreviewTitle} />
        <meta property="og:description" content={albumsPreviewDescription} />
        <meta property="og:image" content={albumsPreviewImage} />
        <meta property="og:image:type" content="image/png" />
        <meta property="og:image:width" content="1200" />
        <meta property="og:image:height" content="630" />
        <meta property="og:image:alt" content="Take a look!" />
        <meta name="twitter:card" content="summary_large_image" />
        <meta name="twitter:title" content={albumsPreviewTitle} />
        <meta name="twitter:description" content={albumsPreviewDescription} />
        <meta name="twitter:image" content={albumsPreviewImage} />
        <meta name="twitter:image:alt" content="Take a look!" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="referrer" content="strict-origin-when-cross-origin" />
    </Head>
);

// Custom API builds must not embed Ente production preview metadata.
export const CustomHeadAlbums: React.FC<CustomHeadProps> = ({ title }) =>
    isCustomAPIOrigin ? (
        <CustomHead {...{ title }}>
            <AlbumsFontPreloads />
        </CustomHead>
    ) : (
        <CustomHeadAlbumsStatic />
    );

const CustomHeadShareStatic: React.FC = () => (
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

export const CustomHeadShare: React.FC<CustomHeadProps> = ({ title }) =>
    isCustomAPIOrigin ? (
        <CustomHead {...{ title }} />
    ) : (
        <CustomHeadShareStatic />
    );
