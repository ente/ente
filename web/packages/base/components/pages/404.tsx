import { useRouter } from "next/router";
import React, { useEffect } from "react";

const Page: React.FC = () => {
    // Return to the app root when a route is unavailable.
    const router = useRouter();

    useEffect(() => {
        void router.push("/");
    }, [router]);

    return <></>;
};

export default Page;
