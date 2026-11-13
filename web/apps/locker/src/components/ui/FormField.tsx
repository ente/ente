import { lockerFieldSx } from "@/styles/fields";
import {
    Box,
    Stack,
    TextField,
    Typography,
    type TextFieldProps,
} from "@mui/material";
import { useId } from "react";

type FormFieldProps = Omit<TextFieldProps, "label"> & {
    label: string;
    multilineMinHeight?: number;
};

export function FormField({
    label,
    required,
    multiline,
    multilineMinHeight,
    ...rest
}: FormFieldProps) {
    const id = useId();

    return (
        <Stack sx={{ gap: "8px" }}>
            <Typography
                variant="small"
                component="label"
                htmlFor={id}
                sx={{
                    fontWeight: 500,
                    lineHeight: "20px",
                    display: "flex",
                    gap: "2px",
                    color: "text.base",
                }}
            >
                {label}
                {required && (
                    <Box
                        component="span"
                        aria-hidden
                        sx={{ color: "critical.main", fontWeight: 600 }}
                    >
                        *
                    </Box>
                )}
            </Typography>
            <TextField
                {...rest}
                id={id}
                required={required}
                multiline={multiline}
                hiddenLabel
                fullWidth
                variant="outlined"
                margin="none"
                sx={(theme) =>
                    lockerFieldSx(theme, {
                        multiline,
                        minHeight: multilineMinHeight,
                    })
                }
            />
        </Stack>
    );
}
