import { Divider, Stack } from "@mui/material";
import type { ReactNode } from "react";

interface MenuGroupComponentProps {
    children: ReactNode;
    dividerInset?: number;
}

export function MenuGroupComponent({
    children,
    dividerInset = 16,
}: MenuGroupComponentProps) {
    return (
        <Stack
            divider={
                <Divider
                    sx={{
                        "&&": { ml: `${dividerInset}px` },
                        borderColor: "fill.fainter",
                    }}
                />
            }
            sx={[
                {
                    bgcolor: "background.paper",
                    borderRadius: "20px",
                    overflow: "hidden",
                    "& > button": { borderRadius: 0 },
                },
                (theme) => theme.applyStyles("dark", { bgcolor: "#212121" }),
            ]}
        >
            {children}
        </Stack>
    );
}
