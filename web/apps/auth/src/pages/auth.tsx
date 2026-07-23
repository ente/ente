import { generateOTPs, type Code } from "@/services/code";
import { getAuthCodesAndTimeOffset } from "@/services/remote";
import { prettyFormatCode } from "@/utils/format";
import LogoutOutlinedIcon from "@mui/icons-material/LogoutOutlined";
import PushPinIcon from "@mui/icons-material/PushPin";
import {
    Box,
    Button,
    ButtonBase,
    Snackbar,
    Stack,
    TextField,
    Typography,
    useTheme,
} from "@mui/material";
import { useColorScheme } from "@mui/material/styles";
import { sessionExpiredDialogAttributes } from "ente-accounts/components/utils/dialog";
import { stashRedirect } from "ente-accounts/services/redirect";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { LoadingIndicator } from "ente-base/components/loaders";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { NavbarBase } from "ente-base/components/Navbar";
import {
    OverflowMenu,
    OverflowMenuOption,
} from "ente-base/components/OverflowMenu";
import { useBaseContext } from "ente-base/context";
import { isHTTP401Error } from "ente-base/http";
import log from "ente-base/log";
import { masterKeyFromSession } from "ente-base/session";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useState } from "react";

const Page: React.FC = () => {
    const { logout, showMiniDialog } = useBaseContext();

    const router = useRouter();
    const [codes, setCodes] = useState<Code[]>([]);
    const [timeOffset, setTimeOffset] = useState(0);
    const [hasFetched, setHasFetched] = useState(false);
    const [searchTerm, setSearchTerm] = useState("");

    useEffect(() => {
        const fetchCodes = async () => {
            const masterKey = await masterKeyFromSession();
            if (!masterKey) {
                stashRedirect("/auth");
                void router.push("/");
                return;
            }

            try {
                const { codes, timeOffset } =
                    await getAuthCodesAndTimeOffset(masterKey);
                setCodes(codes);
                setTimeOffset(timeOffset ?? 0);
            } catch (e) {
                log.error("Failed to fetch codes", e);
                if (isHTTP401Error(e))
                    showMiniDialog(sessionExpiredDialogAttributes(logout));
            }
            setHasFetched(true);
        };
        void fetchCodes();
    }, [router, logout, showMiniDialog]);

    const lcSearch = searchTerm.toLowerCase();
    const filteredCodes = codes.filter(
        (code) =>
            code.issuer.toLowerCase().includes(lcSearch) ||
            code.account?.toLowerCase().includes(lcSearch) ||
            code.codeDisplay?.note?.toLowerCase().includes(lcSearch),
    );

    if (!hasFetched) {
        return <LoadingIndicator />;
    }

    return (
        <Stack>
            <AuthNavbar />
            <Stack
                sx={{
                    maxWidth: "800px",
                    alignItems: "center",
                    justifyContent: "center",
                    margin: "0 auto",
                    mt: 1,
                }}
            >
                {filteredCodes.length == 0 && searchTerm.length == 0 ? (
                    <></>
                ) : (
                    <TextField
                        id="search"
                        name="search"
                        label={t("search")}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        variant="filled"
                        sx={{ minWidth: "min(340px, 80svw)" }}
                        value={searchTerm}
                        autoFocus
                    />
                )}

                <Box
                    sx={{
                        display: "flex",
                        flexDirection: "row",
                        flexWrap: "wrap",
                        justifyContent: "center",
                        mt: 3,
                    }}
                >
                    {filteredCodes.length == 0 ? (
                        <Box sx={{ textAlign: "center", mt: 4 }}>
                            {searchTerm.length > 0 ? (
                                <Typography>{t("no_results")}</Typography>
                            ) : (
                                <Typography sx={{ color: "text.muted" }}>
                                    {t("no_codes_added_yet")}
                                </Typography>
                            )}
                        </Box>
                    ) : (
                        filteredCodes.map((code) => (
                            <CodeDisplay
                                key={code.id}
                                {...{ code, timeOffset }}
                            />
                        ))
                    )}
                </Box>
                <Footer />
            </Stack>
        </Stack>
    );
};

export default Page;

const AuthNavbar: React.FC = () => {
    const { logout } = useBaseContext();

    return (
        <NavbarBase
            sx={{
                position: "sticky",
                top: 0,
                left: 0,
                mb: 2,
                zIndex: 1,
                backgroundColor: "backdrop.muted",
                backdropFilter: "blur(7px)",
            }}
        >
            <EnteLogo />
            <Box sx={{ position: "absolute", right: "24px" }}>
                <OverflowMenu ariaID="auth-options">
                    <OverflowMenuOption
                        color="critical"
                        startIcon={<LogoutOutlinedIcon />}
                        onClick={logout}
                    >
                        {t("logout")}
                    </OverflowMenuOption>
                </OverflowMenu>
            </Box>
        </NavbarBase>
    );
};

interface CodeDisplayProps {
    code: Code;
    timeOffset: number;
}

const CodeDisplay: React.FC<CodeDisplayProps> = ({ code, timeOffset }) => {
    const [otp, setOTP] = useState("");
    const [nextOTP, setNextOTP] = useState("");
    const [errorMessage, setErrorMessage] = useState("");
    const [openCopied, setOpenCopied] = useState(false);

    const regen = useCallback(() => {
        try {
            const [m, n] = generateOTPs(code, timeOffset);
            setOTP(m);
            setNextOTP(n);
        } catch (e) {
            setErrorMessage(e instanceof Error ? e.message : String(e));
        }
    }, [code, timeOffset]);

    const copyCode = () =>
        void navigator.clipboard.writeText(otp).then(() => {
            setOpenCopied(true);
            setTimeout(() => setOpenCopied(false), 2000);
        });

    useEffect(() => {
        // Generate to set the initial otp and nextOTP on component mount.
        regen();

        const periodMs = code.period * 1000;
        const timeToNextCode =
            periodMs - ((Date.now() + timeOffset) % periodMs);

        let interval: ReturnType<typeof setInterval> | undefined;
        // Wait until we are at the start of the next code period, and then
        // start the interval loop.
        setTimeout(() => {
            // We need to call regen() once before the interval loop to set the
            // initial otp and nextOTP.
            regen();
            interval = setInterval(regen, periodMs);
        }, timeToNextCode);

        return () => interval && clearInterval(interval);
    }, [code, timeOffset, regen]);

    return (
        <Box sx={{ p: 1 }}>
            {errorMessage ? (
                <UnparseableCode {...{ code, errorMessage }} />
            ) : (
                <ButtonBase component="div" onClick={copyCode}>
                    <OTPDisplay
                        {...{ code, timeOffset }}
                        otp={prettyFormatCode(otp)}
                        nextOTP={prettyFormatCode(nextOTP)}
                    />
                    <Snackbar
                        open={openCopied}
                        message={t("copied")}
                        slotProps={{
                            content: {
                                sx: {
                                    backgroundColor: "fill.faint",
                                    color: "primary.main",
                                    backdropFilter: "blur(10px)",
                                },
                            },
                        }}
                    />
                </ButtonBase>
            )}
        </Box>
    );
};

type OTPDisplayProps = CodeValidityBarProps & { otp: string; nextOTP: string };

const OTPDisplay: React.FC<OTPDisplayProps> = ({
    code,
    timeOffset,
    otp,
    nextOTP,
}) => {
    const { systemMode } = useColorScheme();
    const isDarkMode = systemMode === "dark";

    return (
        <Box
            sx={(theme) => ({
                position: "relative",
                backgroundColor: theme.vars.palette.background.elevatedPaper,
                borderRadius: "4px",
                overflow: "hidden",
            })}
        >
            <Box sx={{ position: "relative", zIndex: 2 }}>
                <CodeValidityBar {...{ code, timeOffset }} />
            </Box>
            {code.codeDisplay?.pinned && (
                <>
                    <Box
                        sx={{
                            position: "absolute",
                            top: "-5px",
                            right: "-41px",
                            width: "107px",
                            height: "26px",
                            bgcolor: isDarkMode ? "#390C4F" : "#f6f6f6",
                            transform: "rotate(43deg)",
                            zIndex: 0,
                        }}
                    />
                    <PushPinIcon
                        sx={{
                            position: "absolute",
                            top: "6px",
                            right: "5px",
                            fontSize: "14px",
                            color: "#8e2de2",
                            zIndex: 1,
                            transform: "rotate(45deg)",
                        }}
                    />
                </>
            )}
            <Stack
                direction="row"
                sx={{
                    padding: "12px 20px 0px 20px",
                    minWidth: "min(360px, 80svw)",
                    minHeight: "120px",
                    justifyContent: "space-between",
                }}
            >
                <Stack style={{ gap: "4px", alignItems: "flex-start" }}>
                    <Typography variant="small">{code.issuer}</Typography>
                    <Typography
                        variant="mini"
                        sx={{ color: "text.faint", flex: 1, minHeight: "16px" }}
                    >
                        {code.account ?? ""}
                    </Typography>
                    <Typography variant="h3" sx={{ mb: "20px" }}>
                        {otp}
                    </Typography>
                </Stack>
                <Stack
                    sx={{
                        justifyContent: "flex-end",
                        alignItems: "flex-end",
                        textAlign: "right",
                        mb: "1rem",
                        gap: "2px",
                    }}
                >
                    <Typography variant="mini" sx={{ color: "text.faint" }}>
                        {t("auth_next")}
                    </Typography>
                    <Typography
                        variant="small"
                        sx={{ fontWeight: "medium", color: "text.muted" }}
                    >
                        {nextOTP}
                    </Typography>
                </Stack>
            </Stack>
        </Box>
    );
};

interface CodeValidityBarProps {
    code: Code;
    timeOffset: number;
}

const CodeValidityBar: React.FC<CodeValidityBarProps> = ({
    code,
    timeOffset,
}) => {
    const theme = useTheme();
    const [progress, setProgress] = useState(code.type == "hotp" ? 1 : 0);

    useEffect(() => {
        const advance = () => {
            const us = code.period * 1e6;
            const timeRemaining =
                us - (((Date.now() + timeOffset) * 1000) % us);
            setProgress(timeRemaining / us);
        };

        const ticker =
            code.type == "hotp" ? undefined : setInterval(advance, 10);

        return () => ticker && clearInterval(ticker);
    }, [code, timeOffset]);

    const progressColor =
        progress > 0.4
            ? theme.vars.palette.accent.light
            : theme.vars.palette.warning.main;

    return (
        <div
            style={{
                width: `${progress * 100}%`,
                height: "3px",
                backgroundColor: progressColor,
            }}
        />
    );
};

interface UnparseableCodeProps {
    code: Code;
    errorMessage: string;
}

const UnparseableCode: React.FC<UnparseableCodeProps> = ({
    code,
    errorMessage,
}) => {
    const [openCopied, setOpenCopied] = useState(false);

    const copyRawData = () =>
        void navigator.clipboard.writeText(code.uriString).then(() => {
            setOpenCopied(true);
            setTimeout(() => setOpenCopied(false), 2000);
        });

    return (
        <Stack
            sx={(theme) => ({
                backgroundColor: theme.vars.palette.background.elevatedPaper,
                borderRadius: "4px",
                overflow: "hidden",
                p: "16px 20px",
                minWidth: "min(360px, 80svw)",
                maxWidth: "360px",
                minHeight: "120px",
                gap: "4px",
            })}
        >
            <Typography variant="small">{code.issuer}</Typography>
            <Typography
                variant="small"
                sx={{
                    color: "critical.main",
                    flex: 1,
                    minHeight: "16px",
                    mb: 2,
                }}
            >
                {errorMessage}
            </Typography>
            <FocusVisibleButton color="secondary" onClick={copyRawData}>
                Copy raw data
            </FocusVisibleButton>
            <Snackbar open={openCopied} message={t("copied")} />
        </Stack>
    );
};

const Footer: React.FC = () => {
    return (
        <Stack sx={{ my: "4rem", gap: 2, alignItems: "center" }}>
            <Typography>{t("auth_download_mobile_app")}</Typography>
            <a href="https://ente.com/auth/#download-auth" download>
                <Button color="accent">{t("download")}</Button>
            </a>
        </Stack>
    );
};
