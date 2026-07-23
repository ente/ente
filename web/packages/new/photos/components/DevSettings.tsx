import InfoOutlinedIcon from "@mui/icons-material/InfoOutlined";
import {
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    IconButton,
    InputAdornment,
    Link,
    TextField,
    type ModalProps,
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import { ensureOk } from "ente-base/http";
import { getKVS, removeKV, setKV } from "ente-base/kv";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import React, { useEffect, useState } from "react";
import { z } from "zod";
import { SlideUpTransition } from "./mui/SlideUpTransition";

interface DevSettingsProps {
    /** If `true`, then the dialog is shown. */
    open: boolean;
    /** Called when the dialog wants to be closed. */
    onClose: () => void;
}

/**
 * A dialog allowing the user to set the API origin that the app connects to.
 * See: [Note: Configuring custom server].
 */
export const DevSettings: React.FC<DevSettingsProps> = ({ open, onClose }) => {
    const fullScreen = useIsSmallWidth();

    const handleDialogClose: ModalProps["onClose"] = (_, reason: string) => {
        // Don't close on backdrop clicks.
        if (reason != "backdropClick") onClose();
    };

    return (
        <Dialog
            {...{ open, fullScreen }}
            onClose={handleDialogClose}
            slots={{ transition: SlideUpTransition }}
            maxWidth="xs"
            fullWidth
        >
            <Contents {...{ onClose }} />
        </Dialog>
    );
};

type ContentsProps = Pick<DevSettingsProps, "onClose">;

const Contents: React.FC<ContentsProps> = (props) => {
    // We need two nested components.
    //
    // - The initialAPIOrigin cannot be in our parent (the top level
    //   DevSettings) otherwise it gets preserved across dialog reopens instead
    //   of being read from storage on opening the dialog.
    //
    // - The initialAPIOrigin cannot be in our child (Form) because Formik
    //   doesn't have supported for async initial values.
    const [initialAPIOrigin, setInitialAPIOrigin] = useState<
        string | undefined
    >();

    useEffect(
        () =>
            void getKVS("apiOrigin").then((o) => setInitialAPIOrigin(o ?? "")),
        [],
    );

    // Even though this is async, this should be instantaneous, we're just
    // reading the value from the local IndexedDB.
    if (initialAPIOrigin === undefined) return <></>;

    return <Form {...{ initialAPIOrigin }} {...props} />;
};

type FormProps = ContentsProps & {
    /** The initial value of API origin to prefill in the text input field. */
    initialAPIOrigin: string;
};

const Form: React.FC<FormProps> = ({ initialAPIOrigin, onClose }) => {
    const formik = useFormik({
        initialValues: { apiOrigin: initialAPIOrigin },
        validate: ({ apiOrigin }) => {
            try {
                // The expression is not unused, it is used to validate the URL.
                // eslint-disable-next-line @typescript-eslint/no-unused-expressions
                apiOrigin && new URL(apiOrigin);
            } catch {
                return { apiOrigin: "Invalid endpoint" };
            }
            return {};
        },
        onSubmit: async (values, { setSubmitting, setErrors }) => {
            try {
                await updateAPIOrigin(values.apiOrigin);
            } catch (e) {
                // The person using this functionality is likely a developer and
                // might be helped more by the original error instead of a
                // friendlier but less specific message.
                setErrors({
                    apiOrigin: e instanceof Error ? e.message : String(e),
                });
                return;
            }

            setSubmitting(false);
            onClose();
        },
    });

    // Show validation errors only after the form has been submitted once (the
    // touched state of apiOrigin gets set too early, perhaps because of the
    // autoFocus).
    const hasError =
        formik.submitCount > 0 &&
        formik.touched.apiOrigin &&
        !!formik.errors.apiOrigin;

    return (
        <form onSubmit={formik.handleSubmit}>
            <DialogTitle sx={{ "&&": { padding: "24px 24px 12px 24px" } }}>
                {t("developer_settings")}
            </DialogTitle>
            <DialogContent sx={{ "&&": { padding: "0 24px 0 24px" } }}>
                <TextField
                    fullWidth
                    autoFocus
                    name="apiOrigin"
                    label={t("server_endpoint")}
                    placeholder="http://localhost:8080"
                    value={formik.values.apiOrigin}
                    onChange={formik.handleChange}
                    onBlur={formik.handleBlur}
                    error={hasError}
                    helperText={
                        hasError
                            ? formik.errors.apiOrigin
                            : " " /* always show an empty string to prevent a layout shift */
                    }
                    slotProps={{
                        input: {
                            endAdornment: (
                                <InputAdornment position="end">
                                    <Link
                                        href="https://ente.com/help/self-hosting/installation/post-install/#step-6-configure-apps-to-use-your-server"
                                        target="_blank"
                                        rel="noopener"
                                    >
                                        <IconButton
                                            aria-label={t("more_information")}
                                            color="secondary"
                                            edge="end"
                                        >
                                            <InfoOutlinedIcon />
                                        </IconButton>
                                    </Link>
                                </InputAdornment>
                            ),
                        },
                    }}
                />
            </DialogContent>
            <DialogActions sx={{ "&&": { padding: "0 24px 24px 24px" } }}>
                <FocusVisibleButton
                    type="submit"
                    color="accent"
                    fullWidth
                    disabled={formik.isSubmitting}
                >
                    {t("save")}
                </FocusVisibleButton>
                <FocusVisibleButton
                    onClick={onClose}
                    color="secondary"
                    fullWidth
                >
                    {t("cancel")}
                </FocusVisibleButton>
            </DialogActions>
        </form>
    );
};

/**
 * Save {@link origin} to local storage after verifying it with a ping.
 *
 * The given {@link origin} will be verifying by making an API call to the
 * `/ping` endpoint. If that succeeds, then it will be saved to local storage,
 * and all subsequent API calls will use it as the {@link apiOrigin}.
 *
 * See: [Note: Configuring custom server].
 *
 * @param origin The new API origin to use. Pass an empty string to clear the
 * previously saved API origin (if any).
 */
const updateAPIOrigin = async (origin: string) => {
    if (!origin) {
        await removeKV("apiOrigin");
        return;
    }

    const res = await fetch(`${origin}/ping`);
    ensureOk(res);
    try {
        PingResponse.parse(await res.json());
    } catch (e) {
        log.error("Invalid response", e);
        throw new Error("Invalid response", { cause: e });
    }

    await setKV("apiOrigin", origin);
};

const PingResponse = z.object({ message: z.enum(["pong"]) });
