import { styled } from "@mui/material";
import type React from "react";
import { authDisplayFontFamily, authMobileMediaQuery } from "./styles";

export interface ScreenHeaderProps {
    title: React.ReactNode;
    subtitle?: React.ReactNode;
}

export function ScreenHeader({
    title,
    subtitle,
}: ScreenHeaderProps): React.JSX.Element {
    return (
        <ScreenHeaderRoot>
            <ScreenTitle>{title}</ScreenTitle>
            {subtitle && <ScreenSubtitle>{subtitle}</ScreenSubtitle>}
        </ScreenHeaderRoot>
    );
}

const ScreenHeaderRoot = styled("div")({
    display: "flex",
    flexDirection: "column",
    gap: "8px",
});

const ScreenTitle = styled("h1")({
    margin: 0,
    fontFamily: authDisplayFontFamily,
    fontSize: "30px",
    fontWeight: 600,
    lineHeight: "38px",
    textWrap: "pretty",
    color: "var(--photos-auth-text)",
    [authMobileMediaQuery]: { fontSize: "26px", lineHeight: "34px" },
    "@media (min-width: 1600px)": { fontSize: "32px", lineHeight: "40px" },
});

const ScreenSubtitle = styled("p")({
    margin: 0,
    fontSize: "16px",
    fontWeight: 500,
    lineHeight: "24px",
    textWrap: "pretty",
    color: "var(--photos-auth-text-muted)",
    [authMobileMediaQuery]: { fontSize: "13px", lineHeight: "20px" },
});
