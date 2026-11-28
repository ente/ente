import { checkDelivery, type DeliveryDestination } from "@/lib/checkout";
import {
    countriesRequiringPostcode,
    deliveryCountries,
} from "@/lib/deliveryCountries";
import type { PrintBinding } from "@/lib/printProducts";
import {
    dialogActionSx,
    dialogCloseButtonSx,
    dialogDescriptionSx,
    dialogHeaderSx,
    dialogPaperSx,
    dialogTitleSx,
} from "@/theme/dialogs";
import {
    Autocomplete,
    Box,
    Button,
    CircularProgress,
    Collapse,
    Dialog,
    IconButton,
    TextField,
    Typography,
    useMediaQuery,
} from "@mui/material";
import { useState, type SubmitEvent } from "react";
import CheckoutProgressContent, {
    type CheckoutProgress,
} from "./CheckoutProgressContent";
import { CloseIcon, InfoIcon, LocationIcon, SuccessIcon } from "./icons";

type DeliveryCheck =
    | { status: "idle" | "checking" | "available" | "unavailable" }
    | { status: "error"; message: string };

export default function CheckoutDialog({
    cover,
    pages,
    progress,
    onClose,
    onContinue,
}: {
    cover: PrintBinding;
    pages: number;
    progress?: CheckoutProgress;
    onClose: () => void;
    onContinue: (destination: DeliveryDestination) => void;
}) {
    const [country, setCountry] = useState<
        (typeof deliveryCountries)[number] | null
    >(null);
    const [postalCode, setPostalCode] = useState("");
    const [countryText, setCountryText] = useState("");
    const [check, setCheck] = useState<DeliveryCheck>({ status: "idle" });
    const checking = check.status === "checking";
    const reducedMotion = useMediaQuery("(prefers-reduced-motion: reduce)");
    const available = check.status === "available";
    const requiresPostcode =
        country && countriesRequiringPostcode.has(country.code);
    const canCheck =
        countryText === country?.name &&
        (!requiresPostcode || postalCode.trim());
    const message = available
        ? "Free shipping is available to this destination."
        : check.status === "unavailable"
          ? "Shipping isn’t available to this destination."
          : check.status === "error"
            ? check.message
            : "";

    const submit = async (event: SubmitEvent<HTMLFormElement>) => {
        event.preventDefault();
        if (checking || !country || !canCheck) return;
        const destination = {
            countryCode: country.code,
            postalCode: postalCode.trim(),
        };
        if (available) {
            onContinue(destination);
            return;
        }
        setCheck({ status: "checking" });
        try {
            const delivers = await checkDelivery(cover, pages, destination);
            setCheck({ status: delivers ? "available" : "unavailable" });
        } catch (cause) {
            setCheck({
                status: "error",
                message:
                    cause instanceof Error
                        ? cause.message
                        : "Couldn’t check delivery. Please try again.",
            });
        }
    };
    return (
        <Dialog
            open
            onClose={checking || progress ? undefined : onClose}
            maxWidth={false}
            aria-labelledby={
                progress ? "checkout-progress-title" : "delivery-title"
            }
            aria-describedby={
                progress
                    ? "checkout-progress-description"
                    : "delivery-description"
            }
            slotProps={{
                paper: { sx: dialogPaperSx },
                backdrop: { sx: { bgcolor: "rgba(0,0,0,0.5)" } },
            }}
        >
            <Box sx={{ display: "grid" }}>
                <Collapse
                    in={!progress}
                    collapsedSize={300}
                    timeout={reducedMotion ? 0 : 220}
                    unmountOnExit
                    sx={{
                        gridArea: "1 / 1",
                        opacity: progress ? 0 : 1,
                        transitionProperty: "height, opacity",
                    }}
                >
                    <Box
                        component="form"
                        inert={!!progress}
                        onSubmit={submit}
                        sx={{
                            position: "relative",
                            display: "grid",
                            gap: "16px",
                            p: "48px 16px 16px",
                            "& .MuiInputBase-root": { borderRadius: "16px" },
                        }}
                    >
                        <IconButton
                            aria-label="Close"
                            disabled={checking}
                            onClick={onClose}
                            sx={dialogCloseButtonSx}
                        >
                            <CloseIcon sx={{ fontSize: 20 }} />
                        </IconButton>
                        <LocationIcon
                            aria-hidden
                            sx={{ fontSize: 72, my: 3, justifySelf: "center" }}
                        />
                        <Box sx={dialogHeaderSx}>
                            <Typography
                                component="h2"
                                id="delivery-title"
                                sx={dialogTitleSx}
                            >
                                Choose a destination
                            </Typography>
                            <Typography
                                id="delivery-description"
                                sx={dialogDescriptionSx}
                            >
                                Check whether delivery is available in your
                                area.
                            </Typography>
                        </Box>
                        <Autocomplete
                            options={deliveryCountries}
                            value={country}
                            inputValue={countryText}
                            openOnFocus
                            disabled={checking}
                            slotProps={{
                                paper: { sx: { borderRadius: "16px" } },
                            }}
                            getOptionLabel={(option) => option.name}
                            onInputChange={(_, text, reason) => {
                                setCountryText(text);
                                if (reason === "input")
                                    setCheck({ status: "idle" });
                            }}
                            onChange={(_, selected) => {
                                setCountry(selected);
                                setPostalCode("");
                                setCheck({ status: "idle" });
                            }}
                            renderInput={(params) => (
                                <TextField
                                    {...params}
                                    label="Country or region"
                                    margin="none"
                                    required
                                />
                            )}
                        />
                        {requiresPostcode && (
                            <TextField
                                label="Postal code"
                                margin="none"
                                autoComplete="postal-code"
                                required
                                disabled={checking}
                                slotProps={{ htmlInput: { maxLength: 20 } }}
                                value={postalCode}
                                onChange={(event) => {
                                    setPostalCode(event.target.value);
                                    setCheck({ status: "idle" });
                                }}
                            />
                        )}
                        {message && (
                            <Box
                                role="status"
                                sx={{
                                    display: "flex",
                                    alignItems: "center",
                                    gap: "10px",
                                    px: "14px",
                                    py: "12px",
                                    borderRadius: "16px",
                                    bgcolor: available ? "#193524" : "#303030",
                                    color: available ? "#A1E4B3" : "#E2E2E2",
                                    ...(check.status === "unavailable" && {
                                        bgcolor: "#3B2D18",
                                        color: "#F5C478",
                                    }),
                                    fontSize: 14,
                                    lineHeight: "20px",
                                    "& svg": { fontSize: 20, flexShrink: 0 },
                                }}
                            >
                                {available ? <SuccessIcon /> : <InfoIcon />}
                                {message}
                            </Box>
                        )}
                        <Button
                            type="submit"
                            variant="contained"
                            disabled={checking || !canCheck}
                            aria-busy={checking}
                            sx={dialogActionSx}
                        >
                            {checking && (
                                <CircularProgress
                                    size={18}
                                    color="inherit"
                                    aria-hidden
                                />
                            )}
                            {checking
                                ? "Checking delivery…"
                                : available
                                  ? "Upload book & check out"
                                  : "Check delivery"}
                        </Button>
                    </Box>
                </Collapse>
                {progress && <CheckoutProgressContent progress={progress} />}
            </Box>
        </Dialog>
    );
}
