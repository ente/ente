import { prettyFormatCode } from "@/utils/format";
import { Box, Button, Stack, Typography, useTheme } from "@mui/material";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { decryptMetadataJSON } from "ente-base/crypto";
import React, { useEffect, useMemo, useState } from "react";

interface SharedCode {
    startTime: number;
    step: number;
    codes: string;
}

const Page: React.FC = () => {
    const [sharedCode, setSharedCode] = useState<SharedCode | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [timeStatus, setTimeStatus] = useState<number>(-10);
    const [codeDisplay, setCodeDisplay] = useState<CodeDisplay>({
        currentCode: "",
        nextCode: "",
        progress: 0,
    });

    const theme = useTheme();

    const getTimeStatus = (
        currentTime: number,
        startTime: number,
        codesLength: number,
        stepDuration: number,
    ): number => {
        if (currentTime < startTime) return -1;
        const totalDuration = codesLength * stepDuration * 1000;
        if (currentTime > startTime + totalDuration) return 1;
        return 0;
    };

    useEffect(() => {
        const decryptCode = async () => {
            const urlParams = new URLSearchParams(window.location.search);
            const data = urlParams.get("data");
            const header = urlParams.get("header");
            const key = window.location.hash.substring(1);

            if (!(data && header && key)) {
                setError("Invalid URL. Please check the URL.");
                return;
            }

            try {
                const decryptedCode = (await decryptMetadataJSON(
                    {
                        encryptedData: base64URLToBytes(data),
                        decryptionHeader: base64URLToBytes(header),
                    },
                    base64URLToBytes(key),
                )) as SharedCode;
                setSharedCode(decryptedCode);
            } catch (error) {
                console.error("Failed to decrypt data:", error);
                setError(
                    "Failed to get the data. Please check the URL and try again.",
                );
            }
        };
        void decryptCode();
    }, []);

    useEffect(() => {
        if (!sharedCode) return;

        let done = false;

        const updateCode = () => {
            if (done) return;

            const currentTime = Date.now();
            const codes = sharedCode.codes.split(",");
            const status = getTimeStatus(
                currentTime,
                sharedCode.startTime,
                codes.length,
                sharedCode.step,
            );
            setTimeStatus(status);

            if (status === 0) {
                setCodeDisplay(
                    parseCodeDisplay(
                        codes,
                        sharedCode.startTime,
                        sharedCode.step,
                    ),
                );
            }

            requestAnimationFrame(updateCode);
        };

        updateCode();

        return () => {
            done = true;
        };
    }, [sharedCode]);

    const progressBarColor = useMemo(
        () =>
            100 - codeDisplay.progress > 40
                ? theme.vars.palette.accent.light
                : theme.vars.palette.warning.main,
        [theme, codeDisplay.progress],
    );

    return (
        <Stack
            sx={{
                justifyContent: "space-between",
                alignItems: "center",
                height: "100vh",
                padding: "20px",
            }}
        >
            <EnteLogo />

            <Box sx={{ width: "min(100%, 300px)" }}>
                {error && (
                    <Typography
                        sx={{ textAlign: "center", color: "critical.main" }}
                    >
                        {error}
                    </Typography>
                )}
                {timeStatus === -10 && !error && (
                    <Message>{"Decrypting..."}</Message>
                )}
                {timeStatus === -1 && (
                    <Message>
                        Your or the person who shared the code has out of sync
                        time.
                    </Message>
                )}
                {timeStatus === 1 && <Message>The code has expired.</Message>}
                {timeStatus === 0 && (
                    <Box
                        sx={(theme) => ({
                            backgroundColor: "background.elevatedPaper",
                            ...theme.applyStyles("dark", {
                                backgroundColor: "#1c1c1e",
                            }),
                            borderRadius: "10px",
                            pb: "20px",
                            position: "relative",
                        })}
                    >
                        <Box
                            sx={(theme) => ({
                                width: "100%",
                                height: "4px",
                                backgroundColor: "#eee",
                                ...theme.applyStyles("dark", {
                                    backgroundColor: "#333",
                                }),
                                borderRadius: "2px",
                            })}
                        >
                            <div
                                style={{
                                    width: `${100 - codeDisplay.progress}%`,
                                    height: "100%",
                                    backgroundColor: progressBarColor,
                                    borderRadius: "2px",
                                }}
                            />
                        </Box>
                        <div
                            style={{
                                fontSize: "36px",
                                fontWeight: "bold",
                                margin: "10px",
                            }}
                        >
                            {codeDisplay.currentCode}
                        </div>
                        <div
                            style={{
                                position: "absolute",
                                right: "20px",
                                bottom: "20px",
                            }}
                        >
                            <Typography
                                variant="mini"
                                sx={{ color: "text.faint" }}
                            >
                                {codeDisplay.nextCode === ""
                                    ? "Last code"
                                    : "next"}
                            </Typography>
                            {codeDisplay.nextCode !== "" && (
                                <Typography
                                    variant="mini"
                                    sx={{ color: "text.faint" }}
                                >
                                    {codeDisplay.nextCode}
                                </Typography>
                            )}
                        </div>
                    </Box>
                )}
            </Box>

            <Button
                color="accent"
                sx={{
                    backgroundColor: "accent.light",
                    borderRadius: "25px",
                    padding: "15px 30px",
                    marginBottom: "42px",
                }}
                href="https://ente.com/auth"
                target="_blank"
            >
                Try Ente Auth
            </Button>
        </Stack>
    );
};

export default Page;

const base64URLToBytes = (base64URL: string): Uint8Array => {
    const base64 = base64URL.replace(/-/g, "+").replace(/_/g, "/");
    return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
};

interface CodeDisplay {
    currentCode: string;
    nextCode: string;
    progress: number;
}

const parseCodeDisplay = (
    codes: string[],
    startTime: number,
    stepDuration: number,
): CodeDisplay => {
    const currentTime = Date.now();
    const elapsedTime = (currentTime - startTime) / 1000;
    const index = Math.floor(elapsedTime / stepDuration);
    const progress = ((elapsedTime % stepDuration) / stepDuration) * 100;

    return {
        currentCode: prettyFormatCode(codes[index] ?? ""),
        nextCode: prettyFormatCode(codes[index + 1] ?? ""),
        progress,
    };
};

const Message: React.FC<React.PropsWithChildren> = ({ children }) => (
    <Typography variant="h4" style={{ textAlign: "center" }}>
        {children}
    </Typography>
);
