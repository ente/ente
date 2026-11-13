import { FilledCircleCheck } from "@/components/FilledCircleCheck";
import { readCastData } from "@/services/cast-data";
import { isChromecast } from "@/services/chromecast-receiver";
import { imageURLGenerator } from "@/services/render";
import { Stack, styled, Typography } from "@mui/material";
import log from "ente-base/log";
import { useRouter } from "next/router";
import React, { useEffect, useState } from "react";

const Page: React.FC = () => {
    const [isEmpty, setIsEmpty] = useState(false);
    const [imageURL, setImageURL] = useState("");

    const router = useRouter();

    useEffect(() => {
        const pair = () => void router.push("/");

        let stop = false;

        const loop = async () => {
            try {
                const urlGenerator = imageURLGenerator(readCastData()!);
                while (!stop) {
                    const { value: url, done } = await urlGenerator.next();
                    if (done == true || !url) {
                        setIsEmpty(true);
                        setTimeout(pair, 5000);
                        return;
                    }

                    setImageURL(url);
                }
            } catch (e) {
                log.error("Failed to prepare generator", e);
                pair();
            }
        };

        void loop();

        return () => {
            stop = true;
        };
    }, [router]);

    if (isEmpty) return <NoItems />;
    if (!imageURL) return <PairingComplete />;

    return isChromecast() ? (
        <SlideViewChromecast url={imageURL} />
    ) : (
        <SlideView url={imageURL} />
    );
};

export default Page;

const PairingComplete: React.FC = () => {
    return (
        <Message>
            <FilledCircleCheck />
            <Typography variant="h3" sx={{ mt: 2, mb: 2 }}>
                Pairing Complete
            </Typography>
            <Stack sx={{ gap: "4px" }}>
                <Typography>{"We're preparing your album"}</Typography>
                <Typography>This should only take a few seconds.</Typography>
            </Stack>
        </Message>
    );
};

const Message = styled(Stack)`
    height: 100vh;
    justify-content: center;
    align-items: center;
    text-align: center;
    gap: 1rem;
`;

const NoItems: React.FC = () => {
    return (
        <Message>
            <Typography variant="h3">Try another album</Typography>
            <Stack sx={{ gap: "4px" }}>
                <Typography>
                    This album has no photos that can be shown here
                </Typography>
                <Typography>Please try another album</Typography>
            </Stack>
        </Message>
    );
};

interface SlideViewProps {
    url: string;
}

const SlideView: React.FC<SlideViewProps> = ({ url }) => {
    return (
        <SlideView_ style={{ backgroundImage: `url(${url})` }}>
            <img src={url} decoding="sync" alt="" />
        </SlideView_>
    );
};

const SlideView_ = styled("div")`
    height: 100vh;

    background-size: cover;
    background-position: center;
    background-repeat: no-repeat;
    background-blend-mode: multiply;
    background-color: rgba(0, 0, 0, 0.5);

    /* The img gets decoding="sync" to switch seamlessly, but there is no
     * equivalent for the background image, so for large images its switch is
     * visibly non-atomic. The long transition masks this. */
    transition: all 2s;

    img {
        width: 100%;
        height: 100%;
        backdrop-filter: blur(10px);
        object-fit: contain;
    }
`;

// Chromecast devices have trouble with backdrop-filter blur; this variant
// approximates it more cheaply.
const SlideViewChromecast: React.FC<SlideViewProps> = ({ url }) => {
    return (
        <SlideViewChromecast_>
            <img className="svc-bg" src={url} alt="" />
            <img className="svc-content" src={url} decoding="sync" alt="" />
        </SlideViewChromecast_>
    );
};

const SlideViewChromecast_ = styled("div")`
    height: 100vh;

    position: relative;
    overflow: hidden;

    img.svc-bg {
        position: absolute;
        left: 0;
        top: 0;
        width: 100%;
        height: 100%;
        object-fit: cover;
        opacity: 0.1;
    }

    img.svc-content {
        position: relative;
        width: 100%;
        height: 100%;
        object-fit: contain;
    }
`;
