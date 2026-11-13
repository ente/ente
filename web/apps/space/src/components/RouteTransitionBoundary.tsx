import React from "react";
import { useSpaceRouteTransitionPopState } from "utils/route-transitions";

interface SpaceRouteTransitionBoundaryProps {
    children: React.ReactNode;
}

export const SpaceRouteTransitionBoundary: React.FC<
    SpaceRouteTransitionBoundaryProps
> = ({ children }) => {
    useSpaceRouteTransitionPopState();
    return <>{children}</>;
};
