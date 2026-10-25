import type React from "react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { generateOTPs, type Code } from "../../utils/ente/code";
import {
    customAPIHost,
    defaultAPIOrigin,
    setCustomAPIOrigin,
} from "../../utils/ente/origins";
import { sendMessageToBackground } from "../../utils/messaging";
import {
    consumePendingWebLogin,
    getTimeOffset,
    getVaultState,
    login,
    LoginError,
    logout,
    refreshCodes,
    resendEmailCode,
    submitEmailCode,
    submitTwoFactor,
    unlock,
    type LoginResult,
} from "../../utils/vault";

type View =
    | "loading"
    | "loggedOut"
    | "emailCode"
    | "webLogin"
    | "twoFactor"
    | "locked"
    | "unlocked";

export const App = () => {
    const [view, setView] = useState<View>("loading");
    const [email, setEmail] = useState<string | undefined>(undefined);
    const [twoFactorSessionID, setTwoFactorSessionID] = useState<
        string | undefined
    >(undefined);

    const refreshView = useCallback(async () => {
        // Complete a web-app login whose credentials the background stashed.
        try {
            await consumePendingWebLogin();
        } catch {
            // Leave the pending session for a later attempt.
        }
        const state = await getVaultState();
        setEmail(state.email);
        if (state.status === "twoFactor") {
            setTwoFactorSessionID(state.twoFactorSessionID);
        }
        setView(state.status);
    }, []);

    useEffect(() => {
        void refreshView();
    }, [refreshView]);

    if (view === "loading") return <Centered>Loading…</Centered>;

    if (view === "loggedOut")
        return (
            <LoginForm
                onResult={async (
                    result: LoginResult,
                    submittedEmail: string,
                ) => {
                    setEmail(submittedEmail);
                    if (result.status === "twoFactor") {
                        setTwoFactorSessionID(result.sessionID);
                        setView("twoFactor");
                    } else if (result.status === "emailCode") {
                        setView("emailCode");
                    } else {
                        await refreshView();
                    }
                }}
                onWebLogin={() => setView("webLogin")}
            />
        );

    if (view === "webLogin")
        return (
            <WebLoginWaiting
                onDone={refreshView}
                onCancel={() => setView("loggedOut")}
            />
        );

    if (view === "emailCode")
        return (
            <EmailCodeForm
                email={email}
                onResult={async (result) => {
                    if (result.status === "twoFactor") {
                        setTwoFactorSessionID(result.sessionID);
                        setView("twoFactor");
                    } else {
                        await refreshView();
                    }
                }}
            />
        );

    if (view === "twoFactor")
        return (
            <TwoFactorForm
                onSubmit={async (code) => {
                    await submitTwoFactor(code, twoFactorSessionID!);
                    await refreshView();
                }}
            />
        );

    if (view === "locked")
        return (
            <PasswordForm
                title="Unlock your vault"
                subtitle={email}
                buttonLabel="Unlock"
                onSubmit={async (password) => {
                    await unlock(password);
                    await refreshView();
                }}
                extra={
                    <button
                        className="link"
                        onClick={async () => {
                            await logout();
                            await refreshView();
                        }}
                    >
                        Log out
                    </button>
                }
            />
        );

    return (
        <VaultScreen
            onLoggedOut={async () => {
                await logout();
                await refreshView();
            }}
        />
    );
};

const Centered = ({ children }: { children: React.ReactNode }) => (
    <div className="centered">{children}</div>
);

// --- Login ------------------------------------------------------------------

const LoginForm = ({
    onResult,
    onWebLogin,
}: {
    onResult: (result: LoginResult, email: string) => Promise<void>;
    onWebLogin: () => void;
}) => {
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState<string | undefined>();
    const [showServer, setShowServer] = useState(false);

    const submit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError(undefined);
        setBusy(true);
        try {
            const result = await login(email.trim(), password);
            await onResult(result, email.trim());
        } catch (err) {
            setError(messageForError(err));
        } finally {
            setBusy(false);
        }
    };

    return (
        <div className="screen">
            <Header title="Ente Auth" />
            <form onSubmit={submit}>
                <label>
                    Email
                    <input
                        type="email"
                        autoComplete="username"
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                        placeholder="you@example.com"
                        required
                    />
                </label>
                <label>
                    Password
                    <input
                        type="password"
                        autoComplete="current-password"
                        value={password}
                        onChange={(e) => setPassword(e.target.value)}
                        required
                    />
                </label>
                {error && <p className="error">{error}</p>}
                <button type="submit" disabled={busy}>
                    {busy ? "Signing in…" : "Sign in"}
                </button>
            </form>
            <button className="link" onClick={() => setShowServer((s) => !s)}>
                {showServer ? "Hide server" : "Use a self-hosted server"}
            </button>
            {showServer && <ServerPicker />}
            <div className="divider">
                <span>or</span>
            </div>
            <button type="button" className="secondary" onClick={onWebLogin}>
                Sign in via the Ente web app
            </button>
            <p className="hint">
                Opens auth.ente.com. Use this for passkey or email-code logins.
            </p>
        </div>
    );
};

// --- Web login hand-off -----------------------------------------------------

const WebLoginWaiting = ({
    onDone,
    onCancel,
}: {
    onDone: () => Promise<void>;
    onCancel: () => void;
}) => {
    const [busy, setBusy] = useState(true);

    useEffect(() => {
        let active = true;
        const start = async () => {
            try {
                const { started } = await sendMessageToBackground({
                    type: "startWebLogin",
                });
                if (active) setBusy(!started);
            } catch {
                if (active) setBusy(false);
            }
        };
        void start();

        const timer = window.setInterval(async () => {
            try {
                if (await consumePendingWebLogin()) {
                    window.clearInterval(timer);
                    await onDone();
                    return;
                }
            } catch {
                // Keep waiting; a later tick may succeed.
            }
            const state = await getVaultState();
            if (state.status === "unlocked") {
                window.clearInterval(timer);
                await onDone();
            }
        }, 1500);

        return () => {
            active = false;
            window.clearInterval(timer);
        };
    }, [onDone]);

    return (
        <div className="screen">
            <Header
                title="Finish signing in"
                subtitle="Complete the login in the Ente tab we just opened. This window will update automatically."
            />
            <p className="hint">
                {busy ? "Opening Ente…" : "Waiting for login…"}
            </p>
            <button className="link" onClick={onCancel}>
                Cancel
            </button>
        </div>
    );
};

const ServerPicker = () => {
    const [host, setHost] = useState<string | undefined>();
    const [value, setValue] = useState("");
    const [status, setStatus] = useState<string | undefined>();

    useEffect(() => {
        void customAPIHost().then(setHost);
    }, []);

    const save = async () => {
        setStatus(undefined);
        try {
            if (!value.trim() || value.trim() === defaultAPIOrigin) {
                await setCustomAPIOrigin(undefined);
                setHost(undefined);
                setStatus(`Using ${defaultAPIOrigin}`);
            } else {
                await setCustomAPIOrigin(value.trim());
                setHost(await customAPIHost());
                setStatus("Saved");
            }
        } catch (e) {
            setStatus(e instanceof Error ? e.message : "Failed");
        }
    };

    return (
        <div className="server">
            <p className="hint">
                Currently: <code>{host ?? defaultAPIOrigin}</code>
            </p>
            <input
                type="url"
                placeholder={defaultAPIOrigin}
                value={value}
                onChange={(e) => setValue(e.target.value)}
            />
            <button onClick={save}>Save server</button>
            {status && <p className="hint">{status}</p>}
        </div>
    );
};

// --- Reusable password / 2FA forms ------------------------------------------

const PasswordForm = ({
    title,
    subtitle,
    buttonLabel,
    onSubmit,
    extra,
}: {
    title: string;
    subtitle?: string;
    buttonLabel: string;
    onSubmit: (password: string) => Promise<void>;
    extra?: React.ReactNode;
}) => {
    const [password, setPassword] = useState("");
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState<string | undefined>();

    const submit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError(undefined);
        setBusy(true);
        try {
            await onSubmit(password);
        } catch (err) {
            setError(messageForError(err));
        } finally {
            setBusy(false);
        }
    };

    return (
        <div className="screen">
            <Header title={title} subtitle={subtitle} />
            <form onSubmit={submit}>
                <label>
                    Password
                    <input
                        type="password"
                        autoComplete="current-password"
                        value={password}
                        onChange={(e) => setPassword(e.target.value)}
                        autoFocus
                        required
                    />
                </label>
                {error && <p className="error">{error}</p>}
                <button type="submit" disabled={busy}>
                    {busy ? "Working…" : buttonLabel}
                </button>
            </form>
            {extra}
        </div>
    );
};

const TwoFactorForm = ({
    onSubmit,
}: {
    onSubmit: (code: string) => Promise<void>;
}) => {
    const [code, setCode] = useState("");
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState<string | undefined>();

    const submit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError(undefined);
        setBusy(true);
        try {
            await onSubmit(code.trim());
        } catch (err) {
            setError(messageForError(err));
        } finally {
            setBusy(false);
        }
    };

    return (
        <div className="screen">
            <Header
                title="Two-factor authentication"
                subtitle="Enter the code from another device"
            />
            <form onSubmit={submit}>
                <label>
                    Code
                    <input
                        type="text"
                        inputMode="numeric"
                        autoComplete="one-time-code"
                        value={code}
                        onChange={(e) => setCode(e.target.value)}
                        autoFocus
                        required
                    />
                </label>
                {error && <p className="error">{error}</p>}
                <button type="submit" disabled={busy}>
                    {busy ? "Verifying…" : "Verify"}
                </button>
            </form>
        </div>
    );
};

// --- Email verification code form -------------------------------------------

const EmailCodeForm = ({
    email,
    onResult,
}: {
    email?: string;
    onResult: (result: LoginResult) => Promise<void>;
}) => {
    const [code, setCode] = useState("");
    const [busy, setBusy] = useState(false);
    const [resending, setResending] = useState(false);
    const [resent, setResent] = useState(false);
    const [error, setError] = useState<string | undefined>();

    const submit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError(undefined);
        setBusy(true);
        try {
            await onResult(await submitEmailCode(code.trim()));
        } catch (err) {
            setError(messageForError(err));
        } finally {
            setBusy(false);
        }
    };

    const resend = async () => {
        setError(undefined);
        setResending(true);
        try {
            await resendEmailCode();
            setResent(true);
            window.setTimeout(() => setResent(false), 3000);
        } catch (err) {
            setError(messageForError(err));
        } finally {
            setResending(false);
        }
    };

    return (
        <div className="screen">
            <Header
                title="Check your email"
                subtitle={
                    email
                        ? `Enter the code sent to ${email}`
                        : "Enter the code sent to your email"
                }
            />
            <form onSubmit={submit}>
                <label>
                    Code
                    <input
                        type="text"
                        inputMode="numeric"
                        autoComplete="one-time-code"
                        value={code}
                        onChange={(e) => setCode(e.target.value)}
                        autoFocus
                        required
                    />
                </label>
                {error && <p className="error">{error}</p>}
                <button type="submit" disabled={busy}>
                    {busy ? "Verifying…" : "Verify"}
                </button>
            </form>
            <button
                className="link"
                onClick={() => void resend()}
                disabled={resending}
            >
                {resending ? "Sending…" : resent ? "Code sent" : "Resend code"}
            </button>
        </div>
    );
};

// --- Vault / code list ------------------------------------------------------

const VaultScreen = ({ onLoggedOut }: { onLoggedOut: () => Promise<void> }) => {
    const [codes, setCodes] = useState<Code[]>([]);
    const [timeOffset, setTimeOffset] = useState(0);
    const [error, setError] = useState<string | undefined>();
    const [refreshing, setRefreshing] = useState(false);
    const [now, setNow] = useState(Date.now());
    const [query, setQuery] = useState("");

    const load = useCallback(async () => {
        setRefreshing(true);
        setError(undefined);
        try {
            setCodes(await refreshCodes());
            setTimeOffset(await getTimeOffset());
        } catch (e) {
            setError(messageForError(e));
        } finally {
            setRefreshing(false);
        }
    }, []);

    useEffect(() => {
        void load();
        const tick = window.setInterval(() => setNow(Date.now()), 1000);
        return () => window.clearInterval(tick);
    }, [load]);

    const filtered = useMemo(() => {
        const q = query.trim().toLowerCase();
        if (!q) return codes;
        return codes.filter((code) =>
            `${code.issuer ?? ""} ${code.account ?? ""}`
                .toLowerCase()
                .includes(q),
        );
    }, [codes, query]);

    return (
        <div className="screen vault">
            <div className="vault-header">
                <strong>Ente Auth</strong>
                <div className="actions">
                    <button
                        className="icon"
                        title="Refresh"
                        onClick={() => void load()}
                        disabled={refreshing}
                    >
                        ⟳
                    </button>
                    <button
                        className="icon"
                        title="Log out"
                        onClick={() => void onLoggedOut()}
                    >
                        ⎋
                    </button>
                </div>
            </div>
            <div className="search">
                <input
                    type="search"
                    placeholder="Search accounts"
                    aria-label="Search accounts"
                    value={query}
                    onChange={(e) => setQuery(e.target.value)}
                />
                {query && (
                    <button
                        className="icon clear"
                        title="Clear search"
                        onClick={() => setQuery("")}
                    >
                        ✕
                    </button>
                )}
            </div>
            {error && <p className="error">{error}</p>}
            {codes.length === 0 && !error ? (
                <p className="hint">
                    No authenticator items found in this account.
                </p>
            ) : filtered.length === 0 ? (
                <p className="hint">No accounts match “{query.trim()}”.</p>
            ) : (
                <ul className="codes">
                    {filtered.map((code) => (
                        <CodeRow
                            key={code.id}
                            code={code}
                            timeOffset={timeOffset}
                            now={now}
                        />
                    ))}
                </ul>
            )}
        </div>
    );
};

const CodeRow = ({
    code,
    timeOffset,
    now,
}: {
    code: Code;
    timeOffset: number;
    now: number;
}) => {
    const [copied, setCopied] = useState(false);

    const { otp, validFor } = useMemo(() => {
        void now; // recompute on every tick
        return generateOTPs(code, timeOffset);
    }, [code, timeOffset, now]);

    const progress = Number.isFinite(validFor)
        ? Math.min(100, Math.max(0, (validFor / code.period) * 100))
        : 100;

    const copy = async () => {
        await navigator.clipboard.writeText(otp);
        setCopied(true);
        window.setTimeout(() => setCopied(false), 1500);
    };

    return (
        <li className="code-row">
            <div className="meta">
                <span className="issuer">{code.issuer || "Unknown"}</span>
                {code.account && (
                    <span className="account">{code.account}</span>
                )}
            </div>
            <button className="otp" title="Copy" onClick={() => void copy()}>
                <span className="digits">{formatOTP(otp)}</span>
                <span className="progress">
                    <span style={{ width: `${progress}%` }} />
                </span>
                {copied && <span className="copied">Copied</span>}
            </button>
        </li>
    );
};

const formatOTP = (otp: string) =>
    otp.length === 6 ? `${otp.slice(0, 3)} ${otp.slice(3)}` : otp;

// --- Bits -------------------------------------------------------------------

const Header = ({ title, subtitle }: { title: string; subtitle?: string }) => (
    <div className="header">
        <h1>{title}</h1>
        {subtitle && <p className="subtitle">{subtitle}</p>}
    </div>
);

const messageForError = (err: unknown): string => {
    if (err instanceof LoginError) {
        switch (err.code) {
            case "not_registered":
                return "No Ente account found for that email.";
            case "email_mfa_unsupported":
                return "This account uses email verification codes, which this extension does not support yet.";
            case "passkey_unsupported":
                return "This account uses a passkey for two-factor authentication, which this extension does not support yet.";
            case "incorrect_password":
                return "Incorrect password.";
            case "missing_keys":
                return "The server response was missing key attributes.";
            case "locked":
                return "Unlock your vault first.";
            case "not_logged_in":
                return "Your session expired. Please sign in again.";
            default:
                return "Something went wrong.";
        }
    }
    if (err instanceof Error) return err.message;
    return "Something went wrong.";
};
