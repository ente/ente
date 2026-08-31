export type {
    LegacyContactRecord,
    LegacyContactState,
    LegacyInfo,
    LegacyRecoverySession,
    LegacyRecoveryStatus,
    LegacyUser,
} from "ente-legacy-wasm/authenticated";

export interface LegacySuggestedUser {
    id?: number;
    email: string;
}
