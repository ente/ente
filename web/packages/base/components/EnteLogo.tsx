import { styled } from "@mui/material";
import React from "react";
import { enteWordmarkPaths, enteWordmarkViewBox } from "./ente-wordmark";

interface EnteLogoProps {
    height?: number;
}

export const EnteLogo: React.FC<EnteLogoProps> = ({ height }) => (
    <svg
        height={height ?? 18}
        viewBox={enteWordmarkViewBox}
        xmlns="http://www.w3.org/2000/svg"
    >
        {enteWordmarkPaths.map((d, index) => (
            <path key={index} d={d} fill="currentColor" />
        ))}
    </svg>
);

// Remove the inline SVG's baseline gap.
export const EnteLogoBox = styled("div")`
    line-height: 0;
`;
