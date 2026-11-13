import { PairingCode } from "@/components/PairingCode";
import {
    clearCastData,
    readCastData,
    storeCastData,
} from "@/services/cast-data";
import { getCastPayload, register, type Registration } from "@/services/pair";
import { Box, Stack, styled, Typography } from "@mui/material";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import log from "ente-base/log";
import { useRouter } from "next/router";
import React, { useEffect, useState } from "react";
import { advertiseOnChromecast } from "../services/chromecast-receiver";

const Page: React.FC = () => {
    const [registration, setRegistration] = useState<Registration>();
    const pairingCode = registration?.pairingCode;

    const router = useRouter();

    useEffect(() => {
        if (!pairingCode) {
            void register().then(setRegistration);
        } else {
            clearCastData();
            advertiseOnChromecast(
                () => pairingCode,
                () => readCastData()?.collectionID,
            );
        }
    }, [pairingCode]);

    useEffect(() => {
        if (!registration) return;

        const pollTick = async () => {
            try {
                const data = await getCastPayload(registration);
                if (!data) return;

                storeCastData(data);
                await router.push("/slideshow");
            } catch (e) {
                log.warn("Failed to get cast data", e);
                setRegistration(undefined);
            }
        };

        const interval = setInterval(pollTick, 2000);
        return () => clearInterval(interval);
    }, [registration, router]);

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
    /* Chrome 92 does not support svh. */
    height: 100vh;
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
