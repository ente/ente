import Head from "next/head";
import React from "react";

const url = "https://locker.ente.com";
const title = "Ente Locker";
const description =
    "Store your important documents and credentials. Share them with trusted contacts or pass them on in emergencies.";
const image =
    "https://ente.com/static/locker-meta-preview-0db171b861bdbc3262b8289e40cf7efe.png";

export const LockerHead: React.FC = () => (
    <Head>
        <title>{title}</title>
        <meta name="description" content={description} />
        <link rel="icon" type="image/png" href="/images/favicon.png" />
        <meta name="twitter:site" content="@enteio" />
        <meta property="og:type" content="website" />
        <meta property="og:url" content={url} />
        <meta property="og:title" content={title} />
        <meta property="og:description" content={description} />
        <meta property="og:image" content={image} />
        <meta property="og:image:secure_url" content={image} />
        <meta property="og:image:type" content="image/png" />
        <meta property="og:image:width" content="1200" />
        <meta property="og:image:height" content="630" />
        <meta property="og:site_name" content="Locker" />
        <meta name="twitter:card" content="summary_large_image" />
        <meta name="twitter:url" content={url} />
        <meta name="twitter:title" content={title} />
        <meta name="twitter:description" content={description} />
        <meta name="twitter:image" content={image} />
        <meta name="theme-color" content="#1071FF" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="referrer" content="strict-origin-when-cross-origin" />
    </Head>
);
