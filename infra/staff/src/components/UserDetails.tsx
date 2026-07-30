import DeleteIcon from "@mui/icons-material/Delete";
import EditIcon from "@mui/icons-material/Edit";
import {
    Box,
    Button,
    Grid,
    IconButton,
    Paper,
    Switch,
    Table,
    TableBody,
    TableCell,
    TableContainer,
    TableRow,
    Typography,
} from "@mui/material";
import React, { useEffect, useState } from "react";
import { SUCCESS_COLOR } from "../utils";
import { AddOTT } from "./AddOTT";
import { ChangeEmail } from "./ChangeEmail";
import { DeleteAccount } from "./DeleteAccount";
import { Disable2FA } from "./Disable2FA";
import { DisablePasskeys } from "./DisablePasskeys";
import { ToggleEmailMFA } from "./ToggleEmailMFA";
import { UpdateSubscription } from "./UpdateSubscription";

export interface UserDetailsData {
    email: string;
    user: UserTableRow[];
    storage: UserTableRow[];
    subscription: UserTableRow[];
    security: UserTableRow[];
    securityState: {
        emailMFAEnabled: boolean;
        twoFactorEnabled: boolean;
        canDisableEmailMFA: boolean;
    };
}

type UserTableRow =
    | { kind: "text"; label: string; value: string }
    | { kind: "email"; label: string; value: string }
    | { kind: "expiry"; label: string; value: string }
    | { kind: "passkeys"; label: string; enabled: boolean }
    | { kind: "twoFactor"; label: string; enabled: boolean }
    | { kind: "emailMFA"; label: string; enabled: boolean };

type UserSectionKey = "user" | "storage" | "subscription" | "security";

interface UserDetailsProps {
    userData: UserDetailsData;
}

export const UserDetails: React.FC<UserDetailsProps> = ({ userData }) => {
    const [deleteAccountOpen, setDeleteAccountOpen] = useState(false);
    const [emailMFAEnabled, setEmailMFAEnabled] = useState(
        userData.securityState.emailMFAEnabled,
    );
    const [emailMFAOpen, setEmailMFAOpen] = useState(false);
    const [disable2FAOpen, setDisable2FAOpen] = useState(false);
    const [twoFactorEnabled, setTwoFactorEnabled] = useState(
        userData.securityState.twoFactorEnabled,
    );
    const [updateSubscriptionOpen, setUpdateSubscriptionOpen] = useState(false);
    const [changeEmailOpen, setChangeEmailOpen] = useState(false);
    const [disablePasskeysOpen, setDisablePasskeysOpen] = useState(false);
    const [addOTTOpen, setAddOTTOpen] = useState(false);
    const { canDisableEmailMFA } = userData.securityState;

    useEffect(() => {
        // These switches are local after successful mutations, but same-user
        // refetches should still resync them with the server.
        // eslint-disable-next-line react-hooks/set-state-in-effect
        setEmailMFAEnabled(userData.securityState.emailMFAEnabled);
        setTwoFactorEnabled(userData.securityState.twoFactorEnabled);
    }, [
        userData.securityState.emailMFAEnabled,
        userData.securityState.twoFactorEnabled,
    ]);

    const handleEditEmail = () => setChangeEmailOpen(true);
    const handleDeleteAccountClick = () => setDeleteAccountOpen(true);
    const handleEditSubscription = () => setUpdateSubscriptionOpen(true);
    const handleDisablePasskeys = () => setDisablePasskeysOpen(true);
    const handleTwoFactorChange = (enabled: boolean) => {
        if (!enabled) {
            setDisable2FAOpen(true);
        }
    };

    const sections: {
        key: UserSectionKey;
        title: string;
        rows: UserTableRow[];
    }[] = [
        { key: "user", title: "User", rows: userData.user },
        { key: "storage", title: "Storage", rows: userData.storage },
        {
            key: "subscription",
            title: "Subscription",
            rows: userData.subscription,
        },
        { key: "security", title: "Security", rows: userData.security },
    ];
    const tableActions: UserTableActions = {
        editEmail: handleEditEmail,
        deleteAccount: handleDeleteAccountClick,
        editSubscription: handleEditSubscription,
        disablePasskeys: handleDisablePasskeys,
        addOTT: () => setAddOTTOpen(true),
        toggleEmailMFA: () => setEmailMFAOpen(true),
        changeTwoFactor: handleTwoFactorChange,
    };
    const securityControls: SecurityControls = {
        canDisableEmailMFA,
        twoFactorEnabled,
        emailMFAEnabled,
    };

    return (
        <Grid container spacing={6} sx={{ justifyContent: "center" }}>
            {sections.map(({ key, title, rows }) => (
                <Grid size={{ xs: 12, sm: 10, md: 6 }} key={key}>
                    <DataTable
                        sectionKey={key}
                        title={title}
                        rows={rows}
                        actions={tableActions}
                        securityControls={securityControls}
                    />
                </Grid>
            ))}

            <DeleteAccount
                open={deleteAccountOpen}
                handleClose={() => setDeleteAccountOpen(false)}
            />
            <Disable2FA
                open={disable2FAOpen}
                handleClose={() => setDisable2FAOpen(false)}
                handleDisable2FA={() => setTwoFactorEnabled(false)}
            />
            <ToggleEmailMFA
                open={emailMFAOpen}
                handleClose={() => setEmailMFAOpen(false)}
                handleToggleEmailMFA={setEmailMFAEnabled}
            />
            <UpdateSubscription
                open={updateSubscriptionOpen}
                onClose={() => setUpdateSubscriptionOpen(false)}
            />
            <ChangeEmail
                open={changeEmailOpen}
                onClose={() => setChangeEmailOpen(false)}
            />
            <DisablePasskeys
                open={disablePasskeysOpen}
                handleClose={() => setDisablePasskeysOpen(false)}
                handleDisablePasskeys={() => setDisablePasskeysOpen(false)}
            />
            <AddOTT
                open={addOTTOpen}
                onClose={() => setAddOTTOpen(false)}
                userEmail={userData.email}
            />
        </Grid>
    );
};

interface DataTableProps {
    sectionKey: UserSectionKey;
    title: string;
    rows: UserTableRow[];
    actions: UserTableActions;
    securityControls: SecurityControls;
}

interface UserTableActions {
    editEmail: () => void;
    deleteAccount: () => void;
    editSubscription: () => void;
    disablePasskeys: () => void;
    addOTT: () => void;
    toggleEmailMFA: () => void;
    changeTwoFactor: (enabled: boolean) => void;
}

interface SecurityControls {
    canDisableEmailMFA: boolean;
    twoFactorEnabled: boolean;
    emailMFAEnabled: boolean;
}

const DataTable: React.FC<DataTableProps> = ({
    sectionKey,
    title,
    rows,
    actions,
    securityControls,
}) => (
    <TableContainer
        component={Paper}
        variant="outlined"
        sx={{
            backgroundColor: "#F1F1F3",
            minHeight: 300,
            display: "flex",
            flexDirection: "column",
            height: "100%",
            width: "100%",
            padding: "10px",
            overflowX: "hidden",
        }}
    >
        <Box
            sx={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                padding: "16px",
                width: "100%",
            }}
        >
            <Typography
                variant="h6"
                component="div"
                sx={{ fontWeight: "bold", textAlign: "center", width: "100%" }}
            >
                {title}
            </Typography>
            {sectionKey === "user" && (
                <IconButton
                    edge="start"
                    aria-label="delete"
                    onClick={actions.deleteAccount}
                >
                    <DeleteIcon />
                </IconButton>
            )}
            {sectionKey === "subscription" && (
                <IconButton
                    edge="end"
                    aria-label="edit"
                    onClick={actions.editSubscription}
                >
                    <EditIcon sx={{ color: "black", mr: "15px" }} />
                </IconButton>
            )}
        </Box>

        <Table
            sx={{
                width: "100%",
                tableLayout: "fixed",
                height: "100%",
                borderBottom: "none",
            }}
            aria-label={title}
        >
            <TableBody>
                {rows.map((row, index) => (
                    <TableRow key={`${row.kind}:${row.label}`}>
                        <TableCell
                            component="th"
                            scope="row"
                            sx={{
                                p: "16px",
                                borderBottom:
                                    index === 1 || index === 0
                                        ? "1px solid rgba(224, 224, 224, 1)"
                                        : "none",
                            }}
                        >
                            {row.label}
                        </TableCell>
                        <TableCell
                            align="right"
                            sx={{
                                p: "10px",
                                borderBottom:
                                    index === 1 || index === 0
                                        ? "1px solid rgba(224, 224, 224, 1)"
                                        : "none",
                            }}
                        >
                            {renderTableCellContent(
                                row,
                                actions,
                                securityControls,
                            )}
                        </TableCell>
                    </TableRow>
                ))}
                {sectionKey === "security" && (
                    <TableRow>
                        <TableCell
                            component="th"
                            scope="row"
                            sx={{ p: "16px", borderBottom: "none" }}
                        >
                            Add OTT
                        </TableCell>
                        <TableCell
                            align="right"
                            sx={{ p: "10px", borderBottom: "none" }}
                        >
                            <Button
                                variant="contained"
                                onClick={actions.addOTT}
                                sx={{ textTransform: "none" }}
                            >
                                Add OTT
                            </Button>
                        </TableCell>
                    </TableRow>
                )}
            </TableBody>
        </Table>
    </TableContainer>
);

const renderTableCellContent = (
    row: UserTableRow,
    actions: UserTableActions,
    securityControls: SecurityControls,
) => {
    switch (row.kind) {
        case "email":
            return (
                <Box
                    sx={{
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "flex-end",
                    }}
                >
                    <Typography>{row.value}</Typography>
                    <IconButton
                        edge="end"
                        aria-label="edit-email"
                        onClick={actions.editEmail}
                    >
                        <EditIcon sx={{ color: "black" }} />
                    </IconButton>
                </Box>
            );
        case "passkeys":
            return row.enabled ? (
                <Button variant="outlined" onClick={actions.disablePasskeys}>
                    Remove Passkey
                </Button>
            ) : (
                <Typography sx={{ width: "100%", paddingLeft: "1px" }}>
                    {enabledLabel(row.enabled)}
                </Typography>
            );
        case "twoFactor":
            return (
                <Box
                    sx={{
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "flex-end",
                        width: "100%",
                        paddingRight: "50px",
                    }}
                >
                    <Typography sx={{ marginRight: "1px" }}>
                        {enabledLabel(securityControls.twoFactorEnabled)}
                    </Typography>
                    {row.enabled && (
                        <Switch
                            checked={securityControls.twoFactorEnabled}
                            onChange={(e) =>
                                actions.changeTwoFactor(e.target.checked)
                            }
                            sx={successSwitchSx}
                        />
                    )}
                </Box>
            );
        case "expiry": {
            const expiryTime = new Date(row.value);
            const currentTime = new Date();
            const isValidExpiryTime = !Number.isNaN(expiryTime.getTime());
            return (
                <Typography
                    sx={{
                        color:
                            isValidExpiryTime && expiryTime > currentTime
                                ? SUCCESS_COLOR
                                : "red",
                    }}
                >
                    {isValidExpiryTime
                        ? expiryTime.toLocaleString()
                        : row.value}
                </Typography>
            );
        }
        case "emailMFA":
            return (
                <Box
                    sx={{
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "flex-end",
                        width: "100%",
                        paddingRight: "50px",
                    }}
                >
                    <Typography sx={{ marginRight: "1px" }}>
                        {enabledLabel(securityControls.emailMFAEnabled)}
                    </Typography>
                    {securityControls.canDisableEmailMFA && (
                        <Switch
                            checked={securityControls.emailMFAEnabled}
                            onChange={actions.toggleEmailMFA}
                            sx={successSwitchSx}
                        />
                    )}
                </Box>
            );
        default:
            return <Typography>{row.value}</Typography>;
    }
};

const enabledLabel = (enabled: boolean) => (enabled ? "Enabled" : "Disabled");

const successSwitchSx = {
    "& .MuiSwitch-switchBase.Mui-checked": {
        color: "#00B33C",
        "&:hover": { backgroundColor: "rgba(0, 179, 60, 0.08)" },
    },
    "& .MuiSwitch-switchBase.Mui-checked + .MuiSwitch-track": {
        backgroundColor: "#00B33C",
    },
} as const;
