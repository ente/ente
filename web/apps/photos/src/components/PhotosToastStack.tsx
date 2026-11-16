import { Portal, snackbarClasses, styled } from "@mui/material";
import { Notification } from "ente-base/components/Notification";
import {
    createContext,
    useCallback,
    useContext,
    useRef,
    type ComponentProps,
    type PropsWithChildren,
} from "react";

const ToastStackContainer = createContext<(() => HTMLDivElement | null) | null>(
    null,
);

export const PhotosToastStack = ({
    children,
    notificationProps,
}: PropsWithChildren<{
    notificationProps: ComponentProps<typeof Notification>;
}>) => {
    const stackRef = useRef<HTMLDivElement>(null);
    const container = useCallback(() => stackRef.current, []);

    return (
        <ToastStackContainer value={container}>
            <ToastStack ref={stackRef}>
                <Notification {...notificationProps} sx={{ order: 1 }} />
            </ToastStack>
            {children}
        </ToastStackContainer>
    );
};

export const PhotosToastStackPortal = ({ children }: PropsWithChildren) => {
    const container = useContext(ToastStackContainer);
    return <Portal container={container}>{children}</Portal>;
};

const ToastStack = styled("div")(({ theme }) => ({
    position: "fixed",
    right: 24,
    bottom: 24,
    zIndex: theme.zIndex.snackbar,
    display: "flex",
    flexDirection: "column-reverse",
    alignItems: "flex-end",
    gap: 16,
    pointerEvents: "none",
    [theme.breakpoints.down("sm")]: {
        right: 16,
        bottom: "calc(16px + env(safe-area-inset-bottom, 0px))",
    },
    [`& > .${snackbarClasses.root}`]: {
        position: "static",
        pointerEvents: "auto",
        [theme.breakpoints.down("sm")]: { maxWidth: "calc(100vw - 72px)" },
    },
}));
