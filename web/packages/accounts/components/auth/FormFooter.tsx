import { styled } from "@mui/material";
import type React from "react";
import { authMobileMediaQuery } from "./styles";

export function FormFooter({
    children,
}: React.PropsWithChildren): React.JSX.Element {
    return <FormFooterRoot>{children}</FormFooterRoot>;
}

const FormFooterRoot = styled("div")({
    width: "100%",
    display: "flex",
    flexDirection: "column",
    gap: "16px",
    [authMobileMediaQuery]: { marginTop: "auto" },
});
