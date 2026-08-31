import { namedError } from "ente-base/error";

const spaceAuthErrorMessages = {
    account_setup_incomplete: "This account has not finished setup.",
    content_unavailable: "Couldn't prepare your Space. Please try again.",
    email_not_registered: "Email not registered",
    incorrect_credentials: "Incorrect email or password.",
    insufficient_memory: "This device doesn't have enough memory to continue.",
    login_session_expired: "Login session expired. Please sign in again.",
    passkey_session_expired: "Passkey session expired. Please sign in again.",
    signup_incomplete:
        "Account setup incomplete. Create account to finish setup.",
    signup_session_expired: "Signup session expired. Please sign in.",
} satisfies Record<string, string>;

type SpaceAuthErrorName = keyof typeof spaceAuthErrorMessages;

export const spaceAuthError = (name: SpaceAuthErrorName, cause?: unknown) =>
    namedError(name, spaceAuthErrorMessages[name], { cause });

export const spaceAuthErrorMessage = (error: unknown, fallback: string) =>
    error instanceof Error
        ? ((spaceAuthErrorMessages as Record<string, string>)[error.name] ??
          fallback)
        : fallback;
