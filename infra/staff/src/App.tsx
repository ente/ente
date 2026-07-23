import {
    Box,
    Button,
    CircularProgress,
    Tab,
    Tabs,
    TextField,
} from "@mui/material";
import React, {
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";
import "./App.css";
import { AdHocActions } from "./components/AdHocActions";
import { FamilyTable } from "./components/FamilyTable";
import { StorageBonusTableComponent } from "./components/StorageBonusTableComponent";
import { TokensTableComponent } from "./components/TokenTableComponent";
import { UserDetails, type UserDetailsData } from "./components/UserDetails";
import duckieimage from "./components/duckie.png";
import {
    getScheduledDeletions,
    getUser,
    type ScheduledDeletion,
    type UserResponse,
} from "./services/admin-user";
import { StaffSessionProvider } from "./services/session";
import {
    dateFromMicroseconds,
    formatStorageSize,
    SUCCESS_COLOR,
} from "./utils";

export const App: React.FC = () => {
    const [urlCredentials] = useState(readUrlCredentials);
    const [searchInput, setSearchInput] = useState(urlCredentials.email ?? "");
    const [authToken] = useState(
        () => urlCredentials.token ?? localStorage.getItem("token") ?? "",
    );
    const [selectedUserEmail, setSelectedUserEmail] = useState(
        urlCredentials.email ?? "",
    );
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState("");
    const [fetchSuccess, setFetchSuccess] = useState(false);
    const [tabValue, setTabValue] = useState(0);
    const [userData, setUserData] = useState<UserDetailsData | null>(null);
    const [activeUserID, setActiveUserID] = useState<number>();
    const [scheduledDeletions, setScheduledDeletions] = useState<
        ScheduledDeletion[]
    >([]);
    const [scheduledDeletionsLoading, setScheduledDeletionsLoading] =
        useState(false);
    const [scheduledDeletionsLoaded, setScheduledDeletionsLoaded] =
        useState(false);
    const searchRequestID = useRef(0);

    useEffect(() => {
        if (authToken) {
            localStorage.setItem("token", authToken);
        } else {
            localStorage.removeItem("token");
        }
    }, [authToken]);

    const fetchData = useCallback(async (input: string, authToken: string) => {
        const requestID = ++searchRequestID.current;
        setLoading(true);
        setError("");
        setFetchSuccess(false);
        setUserData(null);
        setActiveUserID(undefined);
        setScheduledDeletions([]);
        setScheduledDeletionsLoading(false);
        setScheduledDeletionsLoaded(false);
        try {
            const userSearchInput = input.trim();
            const userResult = await getUser(
                { token: authToken },
                userSearchInput,
            ).catch((error: unknown) => {
                if (
                    error instanceof Error &&
                    error.message === "User not found"
                ) {
                    return undefined;
                }
                throw error;
            });
            if (requestID !== searchRequestID.current) return;
            if (userResult) {
                const userDetailsData = buildUserDetailsData(
                    userResult,
                    userSearchInput,
                );
                setSelectedUserEmail(userDetailsData.email);
                setUserData(userDetailsData);
                setActiveUserID(userResult.user.ID);
            } else {
                if (!userSearchInput.includes("@")) {
                    throw new Error("User not found");
                }
                const scheduled = await getScheduledDeletions(
                    { token: authToken },
                    userSearchInput,
                );
                if (requestID !== searchRequestID.current) return;
                if (scheduled.length === 0) {
                    throw new Error(noSearchableAccountMessage);
                }
                setSelectedUserEmail(userSearchInput);
                setScheduledDeletions(scheduled);
                setScheduledDeletionsLoaded(true);
            }
            setFetchSuccess(true);
        } catch (error) {
            if (requestID !== searchRequestID.current) return;
            console.error("Error fetching data:", error);
            setError(fetchErrorMessage(error));
        } finally {
            if (requestID === searchRequestID.current) setLoading(false);
        }
    }, []);

    const loadScheduledDeletions = useCallback(async () => {
        if (scheduledDeletionsLoaded || scheduledDeletionsLoading) return;
        const requestID = searchRequestID.current;
        setScheduledDeletionsLoading(true);
        try {
            const scheduled = await getScheduledDeletions(
                { token: authToken },
                selectedUserEmail,
            );
            if (requestID !== searchRequestID.current) return;
            setScheduledDeletions(scheduled);
            setScheduledDeletionsLoaded(true);
        } catch (error) {
            if (requestID !== searchRequestID.current) return;
            throw error;
        } finally {
            if (requestID === searchRequestID.current) {
                setScheduledDeletionsLoading(false);
            }
        }
    }, [
        authToken,
        scheduledDeletionsLoaded,
        scheduledDeletionsLoading,
        selectedUserEmail,
    ]);

    useEffect(() => {
        const { email, token } = urlCredentials;
        if (email && token) {
            queueMicrotask(() => {
                fetchData(email, token).catch((error: unknown) =>
                    console.error("Fetch data error:", error),
                );
            });
        }
    }, [fetchData, urlCredentials]);

    const handleSubmit = (event: React.SubmitEvent<HTMLFormElement>) => {
        event.preventDefault();
        fetchData(searchInput, authToken).catch((error: unknown) =>
            console.error("Fetch data error:", error),
        );
    };

    const handleTabChange = (
        _event: React.SyntheticEvent,
        newValue: number,
    ) => {
        setTabValue(newValue);
    };

    const session = useMemo(
        () => ({ email: selectedUserEmail, token: authToken }),
        [authToken, selectedUserEmail],
    );

    return (
        <StaffSessionProvider session={session}>
            <div className="container">
                <form className="input-form" onSubmit={handleSubmit}>
                    <div className="horizontal-group">
                        <a
                            href="https://staff.ente.sh"
                            target="_blank"
                            rel="noopener"
                            className="link-text"
                        >
                            Ente Staff
                        </a>
                        <div className="text-fields">
                            <TextField
                                label="Email"
                                value={searchInput}
                                onChange={(e) => {
                                    setSearchInput(e.target.value);
                                }}
                                size="medium"
                            />
                        </div>
                        <div className="fetch-button-container">
                            <Button
                                className="fetch-button"
                                type="submit"
                                variant="contained"
                                sx={{ px: 2 }}
                            >
                                FETCH
                            </Button>
                            <AdHocActions
                                email={selectedUserEmail}
                                activeUserID={activeUserID}
                                scheduledDeletions={scheduledDeletions}
                                scheduledDeletionsLoading={
                                    scheduledDeletionsLoading
                                }
                                scheduledDeletionsLoaded={
                                    scheduledDeletionsLoaded
                                }
                                disabled={!fetchSuccess || loading}
                                onOpen={loadScheduledDeletions}
                                onRecovered={() =>
                                    fetchData(selectedUserEmail, authToken)
                                }
                            />
                        </div>
                    </div>
                </form>
                <div className="content-container">
                    {loading ? (
                        <CircularProgress
                            sx={{
                                color: "black",
                                top: "200px",
                                position: "fixed",
                            }}
                        />
                    ) : error ? (
                        <div className="error-message">{error}</div>
                    ) : fetchSuccess ? (
                        <>
                            {userData && (
                                <Box
                                    sx={{
                                        width: "100%",
                                        maxWidth: "600px",
                                        bgcolor: "#FAFAFA",
                                        borderRadius: "7px",
                                        position: "relative",
                                        zIndex: 1000,
                                    }}
                                >
                                    <Tabs
                                        value={tabValue}
                                        onChange={handleTabChange}
                                        centered
                                        sx={{
                                            "& .MuiTabs-indicator": {
                                                backgroundColor: SUCCESS_COLOR,
                                                height: "5px",
                                                borderRadius: "20px",
                                            },
                                            "& .MuiTab-root": {
                                                textTransform: "none",
                                            },
                                        }}
                                    >
                                        <Tab label="User" />
                                        <Tab label="Family" />
                                        <Tab label="Bonuses" />
                                        <Tab label="Devices" />
                                    </Tabs>
                                </Box>
                            )}
                            {userData && (
                                <Box
                                    sx={{
                                        width: "100%",
                                        maxWidth: "900px",
                                        bgcolor: "#FAFAFA",
                                        borderRadius: "7px",
                                        padding: "20px",
                                        position: "relative",
                                        zIndex: 999,
                                        marginTop: "16px",
                                    }}
                                >
                                    {tabValue === 0 && (
                                        <UserDetails userData={userData} />
                                    )}
                                    {tabValue === 1 && <FamilyTable />}
                                    {tabValue === 2 && (
                                        <StorageBonusTableComponent />
                                    )}
                                    {tabValue === 3 && <TokensTableComponent />}
                                </Box>
                            )}
                        </>
                    ) : (
                        <img
                            src={duckieimage}
                            alt="duckie"
                            className="empty-state-image"
                        />
                    )}
                </div>
            </div>
        </StaffSessionProvider>
    );
};

const readUrlCredentials = () => {
    const urlParams = new URLSearchParams(window.location.search);
    return { email: urlParams.get("email"), token: urlParams.get("token") };
};

const subscriptionDataNotFoundMessage = "No subscription record for this user";

const noSearchableAccountMessage =
    "No active account or searchable scheduled deletion found. For older deletions, find the user ID in logs and use the existing recovery flow.";

const fetchErrorMessage = (error: unknown) =>
    error instanceof Error ? error.message : "Invalid token or email/user id";

const buildUserDetailsData = (
    userResponse: UserResponse,
    userSearchInput: string,
): UserDetailsData => {
    if (!userResponse.subscription) {
        throw new Error(subscriptionDataNotFoundMessage);
    }

    const { subscription } = userResponse;
    const emailMFAEnabled =
        userResponse.details?.profileData?.isEmailMFAEnabled ?? false;
    const twoFactorEnabled =
        userResponse.details?.profileData?.isTwoFactorEnabled ?? false;
    const passkeysEnabled =
        (userResponse.details?.profileData?.passkeyCount ?? 0) > 0;
    const canDisableEmailMFA =
        userResponse.details?.profileData?.canDisableEmailMFA ?? false;

    return {
        email: userResponse.user.email || userSearchInput,
        user: [
            {
                kind: "text",
                label: "User ID",
                value: `${userResponse.user.ID}`,
            },
            {
                kind: "email",
                label: "Email",
                value: userResponse.user.email || "None",
            },
            {
                kind: "text",
                label: "Creation time",
                value:
                    dateFromMicroseconds(
                        userResponse.user.creationTime,
                    ).toLocaleString() || "None",
            },
        ],
        storage: [
            {
                kind: "text",
                label: "Total",
                value:
                    subscription.storage === 0
                        ? "None"
                        : formatStorageSize(subscription.storage),
            },
            {
                kind: "text",
                label: "Consumed",
                value: formatStorageSize(userResponse.details?.usage),
            },
            {
                kind: "text",
                label: "Bonus",
                value: formatStorageSize(userResponse.details?.storageBonus),
            },
        ],
        subscription: [
            {
                kind: "text",
                label: "Product ID",
                value: subscription.productID || "None",
            },
            {
                kind: "text",
                label: "Provider",
                value: subscription.paymentProvider || "None",
            },
            {
                kind: "expiry",
                label: "Expiry time",
                value:
                    dateFromMicroseconds(
                        subscription.expiryTime,
                    ).toISOString() || "None",
            },
        ],
        security: [
            { kind: "emailMFA", label: "Email MFA", enabled: emailMFAEnabled },
            {
                kind: "twoFactor",
                label: "Two factor 2FA",
                enabled: twoFactorEnabled,
            },
            { kind: "passkeys", label: "Passkeys", enabled: passkeysEnabled },
            {
                kind: "text",
                label: "AuthCodes",
                value: `${userResponse.authCodes}`,
            },
        ],
        securityState: {
            emailMFAEnabled,
            twoFactorEnabled,
            canDisableEmailMFA,
        },
    };
};
