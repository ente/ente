import { Stack, styled } from "@mui/material";

export const Stack100vhCenter = styled(Stack)`
    min-height: 100vh;
    justify-content: center;
    align-items: center;
`;

export const SpacedRow = styled("div")`
    display: flex;
    justify-content: space-between;
    align-items: center;
`;

export const CenteredRow = styled("div")`
    display: flex;
    justify-content: center;
    align-items: center;
`;

export const CenteredFill = styled("div")`
    flex: 1;
    display: flex;
    justify-content: center;
    align-items: center;
`;

export const Overlay = styled("div")`
    position: absolute;
    width: 100%;
    height: 100%;
    top: 0;
    left: 0;
`;
