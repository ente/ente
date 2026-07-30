import Head from "next/head";
import React from "react";
import { onboardingDescription } from "screens/OnboardingScreen";

const spacePreviewTitle = "Ente Space";
const spacePreviewDescription =
    "A private space for sharing everyday moments with friends and family.";
const spaceInvitePreviewTitle = "You're invited to my Space";
const spaceInvitePreviewDescription =
    "See the everyday moments I share on Ente Space.";
const previewImages = {
    home: "https://ente.space/images/meta.png",
    invite: "https://ente.space/images/meta-invite.png",
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
        preview == "invite" ? spaceInvitePreviewTitle : spacePreviewTitle;
    const previewDescription =
        preview == "invite"
            ? spaceInvitePreviewDescription
            : spacePreviewDescription;

    return (
        <Head>
            <meta name="theme-color" content={themeColor} />
            <meta name="robots" content="noindex,nofollow" />
            <meta
                name="description"
                content={preview ? previewDescription : onboardingDescription}
            />
            {previewImage && (
                <>
                    <meta property="og:image" content={previewImage} />
                    <meta property="og:image:type" content="image/png" />
                    <meta property="og:image:width" content="1200" />
                    <meta property="og:image:height" content="630" />
                    <meta name="twitter:card" content="summary_large_image" />
                    <meta name="twitter:image" content={previewImage} />
                    <meta property="og:title" content={previewTitle} />
                    <meta
                        property="og:description"
                        content={previewDescription}
                    />
                    <meta name="twitter:title" content={previewTitle} />
                    <meta
                        name="twitter:description"
                        content={previewDescription}
                    />
                </>
            )}
        </Head>
    );
};
