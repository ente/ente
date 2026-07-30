import React from "react";
import { useSpaceRouteTransitionPopState } from "utils/spaceRouteTransitions";

interface SpaceRouteTransitionBoundaryProps {
    children: React.ReactNode;
}

export const SpaceRouteTransitionBoundary: React.FC<
    SpaceRouteTransitionBoundaryProps
> = ({ children }) => {
    useSpaceRouteTransitionPopState();
    return <>{children}</>;
};
