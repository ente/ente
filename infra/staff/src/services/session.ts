import {
    createContext,
    createElement,
    useContext,
    useRef,
    type PropsWithChildren,
    type RefObject,
} from "react";

export interface StaffSession {
    email: string;
    token: string;
}

const StaffSessionContext = createContext<StaffSession | null>(null);

interface StaffSessionProviderProps {
    session: StaffSession;
}

export const StaffSessionProvider = ({
    children,
    session,
}: PropsWithChildren<StaffSessionProviderProps>) =>
    createElement(StaffSessionContext.Provider, { value: session }, children);

export const useStaffSession = () => {
    const session = useContext(StaffSessionContext);
    if (!session) throw new Error("Staff session provider not found");
    return session;
};

export const useStaffSessionRef = (): RefObject<StaffSession> => {
    const session = useStaffSession();
    const sessionRef = useRef(session);
    sessionRef.current = session;
    return sessionRef;
};

export const useInitialStaffSession = () => {
    const session = useStaffSession();
    return useRef(session).current;
};
