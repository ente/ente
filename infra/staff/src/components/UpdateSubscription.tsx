import CalendarTodayIcon from "@mui/icons-material/CalendarToday";
import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    Button,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    Grid,
    InputAdornment,
    MenuItem,
    Select,
    type SelectChangeEvent,
    TextField,
} from "@mui/material";
import React, { useEffect, useState } from "react";
import DatePicker from "react-datepicker";
import "react-datepicker/dist/react-datepicker.css";
import {
    getSelectedSubscription,
    updateUserSubscription,
} from "../services/admin-user";
import { useInitialStaffSession, useStaffSession } from "../services/session";
import {
    bytesToGB,
    dateFromMicroseconds,
    dateToMicroseconds,
    gbToBytes,
    SUCCESS_COLOR,
} from "../utils";

interface UpdateSubscriptionProps {
    open: boolean;
    onClose: () => void;
}

interface FormValues {
    productId: string;
    provider: string;
    storage: number;
    transactionId: string;
    expiryTime: Date | null;
    userID: number | undefined;
    attributes: { customerID: string; stripeAccountCountry: string };
}

export const UpdateSubscription: React.FC<UpdateSubscriptionProps> = ({
    open,
    onClose,
}) => {
    const [values, setValues] = useState<FormValues>({
        productId: "",
        provider: "",
        storage: 0,
        transactionId: "",
        expiryTime: null,
        userID: undefined,
        attributes: { customerID: "", stripeAccountCountry: "" },
    });

    const [isDatePickerOpen, setIsDatePickerOpen] = useState(false);
    const initialSession = useInitialStaffSession();
    const session = useStaffSession();

    useEffect(() => {
        if (!open) {
            return;
        }

        const fetchData = async () => {
            try {
                const subscription =
                    await getSelectedSubscription(initialSession);
                const expiryTime = dateFromMicroseconds(
                    subscription.expiryTime,
                );

                setValues({
                    productId: subscription.productID || "",
                    provider: subscription.paymentProvider || "",
                    storage: bytesToGB(subscription.storage) || 0,
                    transactionId: subscription.originalTransactionID || "",
                    expiryTime,
                    userID: subscription.userID,
                    attributes: {
                        customerID: subscription.attributes.customerID || "",
                        stripeAccountCountry:
                            subscription.attributes.stripeAccountCountry || "",
                    },
                });
            } catch (error) {
                console.error("Error fetching data:", error);
            }
        };

        fetchData().catch((error: unknown) => {
            console.error("Unhandled promise rejection:", error);
        });
    }, [initialSession, open]);

    const handleCalendarClick = () => {
        setIsDatePickerOpen(true);
    };

    const handleChange = (event: React.ChangeEvent<HTMLInputElement>) => {
        const { name, value } = event.target;
        setValues((values) => ({
            ...values,
            [name]: name === "storage" ? parseInt(value, 10) : value,
        }));
    };

    const handleChangeProvider = (event: SelectChangeEvent) => {
        setValues((values) => ({ ...values, provider: event.target.value }));
    };

    const handleDatePickerChange = (date: Date | null) => {
        setValues((values) => ({ ...values, expiryTime: date }));
        setIsDatePickerOpen(false);
    };

    const handleSubmit = async (
        event: React.SyntheticEvent<HTMLFormElement>,
    ) => {
        event.preventDefault();

        try {
            if (values.userID === undefined) {
                throw new Error("User ID not found");
            }
            if (!values.expiryTime) {
                throw new Error("Expiry time not found");
            }

            await updateUserSubscription(session, {
                userID: values.userID,
                storage: gbToBytes(values.storage),
                expiryTime: dateToMicroseconds(values.expiryTime),
                productID: values.productId,
                paymentProvider: values.provider,
                transactionID: values.transactionId,
                attributes: {
                    customerID: values.attributes.customerID,
                    stripeAccountCountry:
                        values.attributes.stripeAccountCountry,
                },
            });
            onClose();
        } catch (error) {
            if (error instanceof Error) {
                alert(`Failed to update subscription: ${error.message}`);
            } else {
                alert("Failed to update subscription");
            }
        }
    };

    return (
        <Dialog
            open={open}
            onClose={onClose}
            slotProps={{
                backdrop: {
                    style: {
                        backdropFilter: "blur(5px)",
                        backgroundColor: "rgba(255, 255, 255, 0.8)",
                    },
                },
            }}
        >
            <DialogTitle sx={dialogTitleSx}>
                Update Subscription
                <Button onClick={onClose} sx={dialogCloseButtonSx}>
                    <CloseIcon sx={{ color: "black" }} />
                </Button>
            </DialogTitle>
            <DialogContent>
                <form onSubmit={handleSubmit}>
                    <Grid container spacing={4}>
                        <SubscriptionTextField
                            id="productId"
                            label="Product ID"
                            value={values.productId}
                            onChange={handleChange}
                        />
                        <Grid size={6}>
                            <Box sx={fieldWrapperSx}>
                                <Box
                                    component="label"
                                    htmlFor="provider"
                                    sx={fieldLabelSx}
                                >
                                    Provider
                                </Box>
                                <Select
                                    id="provider"
                                    name="provider"
                                    value={values.provider}
                                    onChange={handleChangeProvider}
                                    fullWidth
                                    sx={{ textAlign: "left" }}
                                >
                                    <MenuItem value="stripe">Stripe</MenuItem>
                                    <MenuItem value="appstore">
                                        AppStore
                                    </MenuItem>
                                    <MenuItem value="paypal">PayPal</MenuItem>
                                    <MenuItem value="bitpay">BitPay</MenuItem>
                                    <MenuItem value="None">None</MenuItem>
                                </Select>
                            </Box>
                        </Grid>
                        <SubscriptionTextField
                            id="storage"
                            label="Storage (GB)"
                            type="number"
                            value={values.storage}
                            onChange={handleChange}
                        />
                        <SubscriptionTextField
                            id="transactionId"
                            label="Transaction ID"
                            value={values.transactionId}
                            onChange={handleChange}
                        />
                        <Grid size={6}>
                            <Box sx={fieldWrapperSx}>
                                <Box
                                    component="label"
                                    htmlFor="expiryTime"
                                    sx={fieldLabelSx}
                                >
                                    Expiry Time
                                </Box>
                                <TextField
                                    id="expiryTime"
                                    name="expiryTime"
                                    value={
                                        values.expiryTime instanceof Date
                                            ? values.expiryTime.toLocaleDateString(
                                                  "en-GB",
                                              )
                                            : ""
                                    }
                                    onClick={handleCalendarClick}
                                    slotProps={{
                                        input: {
                                            endAdornment: (
                                                <InputAdornment position="end">
                                                    <CalendarTodayIcon />
                                                </InputAdornment>
                                            ),
                                            readOnly: true,
                                        },
                                    }}
                                    fullWidth
                                />
                                {isDatePickerOpen && (
                                    <DatePicker
                                        showYearDropdown
                                        scrollableYearDropdown
                                        yearDropdownItemNumber={100}
                                        selected={
                                            values.expiryTime instanceof Date
                                                ? values.expiryTime
                                                : null
                                        }
                                        onChange={handleDatePickerChange}
                                        onClickOutside={() =>
                                            setIsDatePickerOpen(false)
                                        }
                                        withPortal
                                        inline
                                    />
                                )}
                            </Box>
                        </Grid>
                    </Grid>
                    <DialogActions sx={{ justifyContent: "center" }}>
                        <Button type="submit" variant="contained" sx={submitSx}>
                            Update
                        </Button>
                    </DialogActions>
                </form>
            </DialogContent>
        </Dialog>
    );
};

type SubscriptionTextFieldId = "productId" | "storage" | "transactionId";

interface SubscriptionTextFieldProps {
    id: SubscriptionTextFieldId;
    label: string;
    type?: string;
    value: string | number;
    onChange: (event: React.ChangeEvent<HTMLInputElement>) => void;
}

const SubscriptionTextField = ({
    id,
    label,
    type,
    value,
    onChange,
}: SubscriptionTextFieldProps) => (
    <Grid size={6}>
        <Box sx={fieldWrapperSx}>
            <Box component="label" htmlFor={id} sx={fieldLabelSx}>
                {label}
            </Box>
            <TextField
                id={id}
                name={id}
                type={type}
                value={value}
                onChange={onChange}
                fullWidth
            />
        </Box>
    </Grid>
);

const dialogTitleSx = { mb: "20px", mt: "20px" };

const dialogCloseButtonSx = { position: "absolute", right: 10, top: 10 };

const fieldWrapperSx = { mb: 1 };

const fieldLabelSx = { display: "block", mb: "4px", textAlign: "left" };

const submitSx = { bgcolor: SUCCESS_COLOR, color: "white" };
