import { styled } from "@mui/material";
import React from "react";

const photo = (name: string) => `/images/about/${name}.webp`;

const Feature: React.FC<{
    title: React.ReactNode;
    cropVisual?: boolean;
    children: React.ReactNode;
}> = ({ title, cropVisual, children }) => (
    <section className={cropVisual ? "feature cropVisual" : "feature"}>
        <div className="featureHeading">
            <h2>{title}</h2>
        </div>
        {children}
    </section>
);

const FeedPreview: React.FC = () => (
    <img
        className="feedPreview"
        src={photo("feed-screen")}
        alt="Space’s feed showing Sophie’s cat by the window and Chloe’s bookshelf."
        width={780}
        height={1560}
        loading="lazy"
    />
);

export const SpaceAboutContent: React.FC<{ children: React.ReactNode }> = ({
    children,
}) => (
    <Content>
        <section className="hero green-bg">
            <div className="heroCopy">
                <h2>Share everyday photos with your people.</h2>
            </div>
            <div className="heroVisual">
                <FeedPreview />
            </div>
        </section>

        <Feature
            title={
                <>
                    No brain rot. No ads.
                    <br />
                    Just your friends.
                </>
            }
            cropVisual
        >
            <div className="quietVisual">
                <img
                    className="quietIllustration"
                    src="/images/ducky-space.svg"
                    alt=""
                    width={282}
                    height={246}
                    loading="lazy"
                />
            </div>
        </Feature>

        <Feature title="See what your friends and family are up to." cropVisual>
            <div className="screenPreview shortPreview">
                <img
                    className="screenCapture"
                    src={photo("friends-screen")}
                    alt="Further down the feed: Ben’s pancakes, Alex’s park photos, and Emma’s walk around Laurelhurst Park."
                    width={780}
                    height={1768}
                    loading="lazy"
                />
            </div>
        </Feature>

        <Feature title="Like and reply to their posts." cropVisual>
            <div className="screenPreview chatPreview">
                <img
                    className="screenCapture"
                    src={photo("chat-screen")}
                    alt="Alex replies to Ben’s breakfast post, ‘i owe you half a pancake’. Ben answers, ‘You can get coffee next time’."
                    width={780}
                    height={1020}
                    loading="lazy"
                />
            </div>
        </Feature>

        <Feature title="Poke a friend who hasn’t posted in a while." cropVisual>
            <div className="screenPreview pokePreview">
                <img
                    className="screenCapture"
                    src={photo("poke-screen")}
                    alt="Alex pokes Liam, who posts his first photo in over two weeks. Alex replies to the bike photo, ‘fixed it??’. Liam replies, ‘Noah did. I was about to buy a new tire’."
                    width={780}
                    height={1160}
                    loading="lazy"
                />
            </div>
        </Feature>

        <Feature
            title={
                <>
                    Truly private with
                    <br />
                    end-to-end encryption.
                </>
            }
            cropVisual
        >
            <div className="privacyVisual">
                <img
                    className="privacyIllustration"
                    src="/images/about/ducky-encryption.svg"
                    alt=""
                    width={410}
                    height={300}
                    loading="lazy"
                />
            </div>
        </Feature>

        <section className="closing green-bg">
            <h2 className="tagline">More social, less media.</h2>
            {children}
        </section>
    </Content>
);

const Content = styled("div")`
    display: flex;
    flex-direction: column;
    gap: 24px;
    color: #202522;
    font-family: "Inter Variable", Inter, sans-serif;

    & * {
        box-sizing: border-box;
    }

    & h2 {
        max-width: 260px;
        margin: 0 auto;
        font-family: Nunito, sans-serif;
        font-size: clamp(24px, 6.7vw, 30px);
        font-weight: 800;
        letter-spacing: -0.8px;
        line-height: 1.08;
        text-wrap: balance;
    }

    .hero,
    .feature,
    .closing {
        border-radius: 32px;
        overflow: hidden;
    }

    .hero,
    .closing {
        background-color: #08c225;
        color: #fff;
    }

    .heroCopy,
    .featureHeading {
        padding-block: 48px 42px;
        text-align: center;
    }

    .heroCopy {
        padding-inline: 24px;
    }

    .heroVisual,
    .screenPreview {
        padding: 8px;
        overflow: hidden;
        border-radius: 30px 30px 0 0;
    }

    .heroVisual {
        width: calc(100% - 48px);
        max-width: 320px;
        aspect-ratio: 4 / 5.7;
        margin: 0 auto -8px;
        background: #fff6;
        box-shadow: 0 12px 28px #073d1724;
    }

    .feedPreview,
    .screenCapture {
        display: block;
        width: 100%;
        height: auto;
        padding-top: 4px;
        border-radius: 22px 22px 0 0;
        background: #1c1c1e;
    }

    .quietVisual {
        width: 84%;
        max-width: 260px;
        aspect-ratio: 4 / 2.72;
        margin: 0 auto;
        overflow: hidden;
        transform: translateX(4px);
    }

    .quietIllustration {
        display: block;
        width: 100%;
        height: auto;
        margin: 0 auto;
    }

    .screenPreview {
        width: 100%;
        max-width: 350px;
        aspect-ratio: 4 / 5.3;
        margin: 0 auto -8px;
        background: #59665d;
        box-shadow: 0 10px 22px #18281c15;
    }

    .chatPreview,
    .pokePreview {
        aspect-ratio: auto;
    }

    .shortPreview {
        aspect-ratio: 4 / 4.95;
    }

    .feature {
        padding: 0 20px 24px;
        background: #e9ece7;
    }

    .feature.cropVisual {
        padding-bottom: 0;
    }

    .featureHeading {
        position: relative;
        z-index: 1;
    }

    .heroCopy h2,
    .feature:has(.pokePreview) h2 {
        max-width: none;
        font-size: clamp(22px, 6.7vw, 30px);
    }

    .feature:has(.privacyVisual) h2 {
        max-width: none;
    }

    .privacyVisual {
        position: relative;
        width: 100%;
        max-width: 330px;
        min-height: 0;
        aspect-ratio: 4 / 2.4;
        margin: 0 auto;
    }

    .privacyIllustration {
        display: block;
        width: 100%;
        height: auto;
        transform: translate(-8px, -5px) rotate(-42deg);
    }

    .closing {
        display: flex;
        flex-direction: column;
        gap: 80px;
        padding: 80px 24px 32px;
        color: #18211b;
    }

    & .tagline {
        max-width: none;
        color: #d9ffd8;
        text-align: center;
        white-space: nowrap;
    }

    @media (min-width: 440px) {
        .heroCopy,
        .featureHeading {
            padding-top: 54px;
        }

        .heroCopy {
            padding-inline: 36px;
        }

        .feature {
            padding: 0 28px 28px;
        }
    }

    @media (max-width: 359px) {
        .heroCopy,
        .featureHeading {
            padding-top: 44px;
        }

        .heroCopy {
            padding-inline: 20px;
        }

        .feature {
            padding-right: 16px;
            padding-left: 16px;
        }
    }
`;
