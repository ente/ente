import { SpaceLoadingSpinner } from "components/SpaceRouteFallback";
import React from "react";

export const SpaceButtonSpinner: React.FC = () => (
    <SpaceLoadingSpinner
        ariaLabel="Loading"
        color="currentColor"
        size={20}
        trackColor="rgba(255, 255, 255, 0.38)"
    />
);
