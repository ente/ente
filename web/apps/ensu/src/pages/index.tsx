import { LoadingIndicator } from "ente-base/components/loaders";
import { useRouter } from "next/router";
import React, { useEffect } from "react";

const Page: React.FC = () => {
    const router = useRouter();

    useEffect(() => {
        void router.replace("/chat");
    }, [router]);

    return <LoadingIndicator />;
};

export default Page;
