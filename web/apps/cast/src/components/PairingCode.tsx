import { styled } from "@mui/material";
import React from "react";

const colors = [
    "#87CEFA",
    "#90EE90",
    "#F08080",
    "#FFFFE0",
    "#FFB6C1",
    "#E0FFFF",
    "#FAFAD2",
    "#87CEFA",
    "#D3D3D3",
    "#B0C4DE",
    "#FFA07A",
    "#20B2AA",
    "#778899",
    "#AFEEEE",
    "#7A58C1",
    "#FFA500",
    "#A0522D",
    "#9370DB",
    "#008080",
    "#808000",
];

interface PairingCodeProps {
    code: string;
}

export const PairingCode: React.FC<PairingCodeProps> = ({ code }) => {
    return (
        <PairingCode_>
            {code.split("").map((char, i) => (
                <span
                    key={i}
                    style={{
                        backgroundColor: i % 2 === 0 ? "#2e2e2e" : "#5e5e5e",
                        color: colors[i % colors.length],
                    }}
                >
                    {char}
                </span>
            ))}
        </PairingCode_>
    );
};

const PairingCode_ = styled("div")`
    border-radius: 10px;
    overflow: hidden;

    font-size: 4rem;
    font-weight: bold;
    font-family: monospace;

    line-height: 1.2;

    /* inline-block: no extra whitespace when the code is copy pasted, while
     * still getting block level padding. */
    span {
        display: inline-block;
        padding: 0.5rem;
    }
`;
