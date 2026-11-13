import React, { useEffect } from "react";

const Page: React.FC = () => {
    useEffect(() => {
        window.location.href = "https://ente.com";
    }, []);

    return <></>;
};

export default Page;
