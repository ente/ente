import { styled } from "@mui/material";
import type React from "react";

export function FormFields({
    children,
}: React.PropsWithChildren): React.JSX.Element {
    return <FormFieldsRoot>{children}</FormFieldsRoot>;
}

const FormFieldsRoot = styled("div")({
    "--auth-ui-message-gap": "16px",
    width: "100%",
    display: "flex",
    flexDirection: "column",
    gap: "16px",
});
