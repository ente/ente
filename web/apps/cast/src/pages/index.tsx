import { PairingCode } from "@/components/PairingCode";
import { readCastData, storeCastData } from "@/services/cast-data";
import { getCastPayload, register } from "@/services/pair";
import { Box, Stack, styled, Typography } from "@mui/material";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import log from "ente-base/log";
import { useRouter } from "next/router";
import React, { useEffect, useState } from "react";
import { advertiseOnChromecast } from "../services/chromecast-receiver";

const Page: React.FC = () => {
    const [publicKey, setPublicKey] = useState<string | undefined>();
    const [privateKey, setPrivateKey] = useState<string | undefined>();
    const [pairingCode, setPairingCode] = useState<string | undefined>();

    const router = useRouter();

    useEffect(() => {
        if (!pairingCode) {
            void register().then((r) => {
                setPublicKey(r.publicKey);
                setPrivateKey(r.privateKey);
                setPairingCode(r.pairingCode);
            });
        } else {
            advertiseOnChromecast(
                () => pairingCode,
                () => readCastData()?.collectionID,
            );
        }
    }, [pairingCode]);

    useEffect(() => {
        if (!publicKey || !privateKey || !pairingCode) return;

        const pollTick = async () => {
            try {
                const data = await getCastPayload({
                    publicKey,
                    privateKey,
                    pairingCode,
                });
                if (!data) {
                    // No one has connected yet.
                    return;
                }

                storeCastData(data);
                await router.push("/slideshow");
            } catch (e) {
                // The pairing code becomes invalid after an hour, which will cause
                // `getCastData` to fail. There might be other reasons this might
                // fail too, but in all such cases, it is a reasonable idea to start
                // again from the beginning.
                log.warn("Failed to get cast data", e);
                setPairingCode(undefined);
            }
        };

        const interval = setInterval(pollTick, 2000);
        return () => clearInterval(interval);
    }, [publicKey, privateKey, pairingCode, router]);

    return (
        <Container>
            <EnteLogo height={45} />
            <Typography variant="h2" sx={{ marginBlock: "2rem" }}>
                Enter this code on <b>Ente Photos</b> to pair this screen
            </Typography>
            {pairingCode ? <PairingCode code={pairingCode} /> : <Spinner />}
            <Typography variant="h6" sx={{ fontWeight: "regular", mt: 3 }}>
                Visit{" "}
                <a href="https://ente.com/cast" target="_blank" rel="noopener">
                    ente.com/cast
                </a>{" "}
                for help
            </Typography>
        </Container>
    );
};

export default Page;

const Container = styled(Stack)`
    height: 100svh;
    justify-content: center;
    align-items: center;
    text-align: center;

    a {
        text-decoration: none;
        color: #87cefa;
        font-weight: bold;
    }
`;

const Spinner: React.FC = () => (
    <Box
        // Roughly same height as pairing code section to reduce layout shift.
        sx={{ my: "1.7rem" }}
    >
        <ActivityIndicator />
    </Box>
);
