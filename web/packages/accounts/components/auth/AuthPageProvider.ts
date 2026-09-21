import type { SessionStorageCrypto } from "ente-base/session-storage";
import {
    createContext,
    useContext,
    type ComponentType,
    type PropsWithChildren,
} from "react";
import type { VerifyingPasskeyPresentationProps } from "../LoginComponents";
import type { AuthPageShellProps } from "./AuthPageShell";

export interface AuthLoginFrameProps extends PropsWithChildren {
    onHostChanged: () => void;
}

export interface AuthPageConfig {
    decryptBox: SessionStorageCrypto["decryptBox"];
    LoginFrame?: ComponentType<AuthLoginFrameProps>;
    keepLoginLoadingOnRedirect?: boolean;
    recoveryKeyCloseDestination?: string;
    encryptWithRecoveryKey?: (
        data: string,
    ) => Promise<{ encryptedData: string; nonce: string }>;
    passkeyPresentation?: ComponentType<VerifyingPasskeyPresentationProps>;
    Shell: ComponentType<Pick<AuthPageShellProps, "children" | "contentWidth">>;
}

const AuthPageContext = createContext<AuthPageConfig | undefined>(undefined);

export const AuthPageProvider = AuthPageContext.Provider;

export const useAuthPageConfig = (): AuthPageConfig => {
    const config = useContext(AuthPageContext);
    if (!config)
        throw new Error("AuthPageProvider is required for account pages");
    return config;
};
