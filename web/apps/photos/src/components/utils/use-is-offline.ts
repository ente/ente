import { useEffect, useState } from "react";

export const useIsOffline = () => {
    const [offline, setOffline] = useState(
        typeof window != "undefined" && !window.navigator.onLine,
    );

    useEffect(() => {
        const setUserOnline = () => setOffline(false);
        const setUserOffline = () => setOffline(true);

        window.addEventListener("online", setUserOnline);
        window.addEventListener("offline", setUserOffline);

        return () => {
            window.removeEventListener("online", setUserOnline);
            window.removeEventListener("offline", setUserOffline);
        };
    }, []);

    return offline;
};
