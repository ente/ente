import { SpaceLoadingSpinner } from "components/RouteFallback";
import React from "react";

export const SpaceButtonSpinner: React.FC = () => (
    <SpaceLoadingSpinner
        ariaLabel="Loading"
        color="currentColor"
        size={20}
        trackColor="color-mix(in srgb, currentColor 30%, transparent)"
    />
);
