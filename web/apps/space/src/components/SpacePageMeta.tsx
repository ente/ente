import Head from "next/head";
import React from "react";
import { onboardingDescription } from "screens/OnboardingScreen";

const spacePreviewTitle = "Ente Space";
const spacePreviewDescription =
    "A private space for sharing everyday moments with friends and family.";
const previewImages = {
    home: "https://ente.space/images/meta.jpg",
    invite: "https://ente.space/images/meta-invite.jpg",
} as const;

interface SpacePageMetaProps {
    preview?: keyof typeof previewImages;
    themeColor: string;
}

export const SpacePageMeta: React.FC<SpacePageMetaProps> = ({
    preview,
    themeColor,
}) => {
    const previewImage = preview && previewImages[preview];
    const previewTitle =
        preview == "invite" ? "Add me on Ente Space" : spacePreviewTitle;

    return (
        <Head>
            <meta name="theme-color" content={themeColor} />
            <meta name="robots" content="noindex,nofollow" />
            <meta
                name="description"
                content={
                    preview ? spacePreviewDescription : onboardingDescription
                }
            />
            {previewImage && (
                <>
                    <meta property="og:image" content={previewImage} />
                    <meta property="og:image:type" content="image/jpeg" />
                    <meta property="og:image:width" content="1200" />
                    <meta property="og:image:height" content="630" />
                    <meta name="twitter:card" content="summary_large_image" />
                    <meta name="twitter:image" content={previewImage} />
                    <meta property="og:title" content={previewTitle} />
                    <meta
                        property="og:description"
                        content={spacePreviewDescription}
                    />
                    <meta name="twitter:title" content={previewTitle} />
                    <meta
                        name="twitter:description"
                        content={spacePreviewDescription}
                    />
                </>
            )}
        </Head>
    );
};
