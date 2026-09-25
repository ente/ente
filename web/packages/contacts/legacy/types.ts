interface LegacyUser {
    id: number;
    email: string;
}

export interface LegacyContactRecord {
    user: LegacyUser;
    emergencyContact: LegacyUser;
    state:
        | "INVITED"
        | "REVOKED"
        | "ACCEPTED"
        | "CONTACT_LEFT"
        | "CONTACT_DENIED";
    recoveryNoticeInDays: number;
}

export interface LegacyRecoverySession {
    id: string;
    user: LegacyUser;
    emergencyContact: LegacyUser;
    status:
        | "INITIATED"
        | "WAITING"
        | "REJECTED"
        | "RECOVERED"
        | "STOPPED"
        | "READY";
    waitTill: number;
    createdAt: number;
}

export interface LegacyInfo {
    contacts: LegacyContactRecord[];
    recoverSessions: LegacyRecoverySession[];
    othersEmergencyContact: LegacyContactRecord[];
    othersRecoverySession: LegacyRecoverySession[];
}

export interface LegacySuggestedUser {
    id?: number;
    email: string;
}

export interface LegacyModule<Session> {
    getInfo: (session: Session) => Promise<LegacyInfo>;
    publicKey: (session: Session, email: string) => Promise<string | undefined>;
    verificationID: (publicKeyB64: string) => Promise<string>;
    addContact: (
        session: Session,
        email: string,
        recoveryNoticeInDays?: number,
    ) => Promise<void>;
    updateContact: (
        session: Session,
        userID: number,
        emergencyContactID: number,
        state: LegacyContactRecord["state"],
    ) => Promise<void>;
    updateRecoveryNotice: (
        session: Session,
        emergencyContactID: number,
        recoveryNoticeInDays: number,
    ) => Promise<void>;
    startRecovery: (
        session: Session,
        userID: number,
        emergencyContactID: number,
    ) => Promise<void>;
    stopRecovery: (
        session: Session,
        recoveryID: string,
        userID: number,
        emergencyContactID: number,
    ) => Promise<void>;
    rejectRecovery: (
        session: Session,
        recoveryID: string,
        userID: number,
        emergencyContactID: number,
    ) => Promise<void>;
    changePassword: (
        session: Session,
        recoveryID: string,
        newPassword: string,
    ) => Promise<void>;
}
