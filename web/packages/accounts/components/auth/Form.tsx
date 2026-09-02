import { styled } from "@mui/material";
import type React from "react";
import { authMobileMediaQuery } from "./styles";

export interface FormProps extends React.FormHTMLAttributes<HTMLFormElement> {
    children: React.ReactNode;
}

export function Form({ children, ...formProps }: FormProps): React.JSX.Element {
    return <FormRoot {...formProps}>{children}</FormRoot>;
}

const FormRoot = styled("form")({
    width: "100%",
    minHeight: "min-content",
    display: "flex",
    flexDirection: "column",
    gap: "24px",
    [authMobileMediaQuery]: { flex: 1 },
});
