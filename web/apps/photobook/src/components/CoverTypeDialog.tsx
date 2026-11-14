import {
    getPrintBindingLabel,
    PRINT_BINDINGS,
    type PrintBinding,
} from "@/lib/printProducts";
import { accentGreen } from "@/theme/buttons";
import { toolbarColors } from "@/theme/colors";
import {
    dialogActionSx,
    dialogCloseButtonSx,
    dialogDescriptionSx,
    dialogHeaderSx,
    dialogPaperSx,
    dialogTitleSx,
} from "@/theme/dialogs";
import {
    Box,
    Button,
    Dialog,
    FormControlLabel,
    IconButton,
    Radio,
    RadioGroup,
    Typography,
} from "@mui/material";
import { useState } from "react";
import { BookIcon, CloseIcon } from "./icons";

export default function CoverTypeDialog({
    onContinue,
    onClose,
}: {
    onContinue: (cover: PrintBinding) => void;
    onClose: () => void;
}) {
    const [cover, setCover] = useState<PrintBinding>();
    return (
        <Dialog
            open
            onClose={onClose}
            maxWidth={false}
            aria-labelledby="cover-type-title"
            aria-describedby="cover-type-description"
            slotProps={{
                paper: { sx: dialogPaperSx },
                backdrop: { sx: { bgcolor: "rgba(0,0,0,0.5)" } },
            }}
        >
            <Box
                component="form"
                onSubmit={(event) => {
                    event.preventDefault();
                    if (cover) onContinue(cover);
                }}
                sx={{
                    position: "relative",
                    display: "grid",
                    justifyItems: "center",
                    gap: 2,
                    p: "48px 16px 16px",
                }}
            >
                <IconButton
                    aria-label="Close"
                    onClick={onClose}
                    sx={dialogCloseButtonSx}
                >
                    <CloseIcon sx={{ fontSize: 20 }} />
                </IconButton>
                <BookIcon aria-hidden sx={{ fontSize: 72, my: 3 }} />
                <Box sx={dialogHeaderSx}>
                    <Typography
                        component="h2"
                        id="cover-type-title"
                        sx={dialogTitleSx}
                    >
                        Choose type
                    </Typography>
                    <Typography
                        id="cover-type-description"
                        sx={dialogDescriptionSx}
                    >
                        Which type of photobook would you like?
                    </Typography>
                </Box>
                <RadioGroup
                    aria-labelledby="cover-type-title"
                    value={cover ?? ""}
                    sx={{ width: "100%", gap: 1 }}
                >
                    {PRINT_BINDINGS.map((option) => (
                        <FormControlLabel
                            key={option}
                            value={option}
                            label={getPrintBindingLabel(option)}
                            control={
                                <Radio
                                    disableRipple
                                    onChange={() => setCover(option)}
                                />
                            }
                            sx={{
                                m: 0,
                                py: 0.5,
                                borderRadius: "12px",
                                bgcolor: toolbarColors.background,
                                "&:has(input:focus-visible)": {
                                    outline: `2px solid ${accentGreen}`,
                                    outlineOffset: 2,
                                },
                            }}
                        />
                    ))}
                </RadioGroup>
                <Button
                    type="submit"
                    variant="contained"
                    fullWidth
                    disabled={!cover}
                    sx={dialogActionSx}
                >
                    Continue
                </Button>
            </Box>
        </Dialog>
    );
}
