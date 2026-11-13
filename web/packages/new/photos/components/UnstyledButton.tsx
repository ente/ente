import { styled } from "@mui/material";

export const UnstyledButton = styled("button")`
    background: transparent;
    border: 0;
    padding: 0;

    font: inherit;
    letter-spacing: inherit;

    cursor: pointer;
`;

export const FocusVisibleUnstyledButton = styled(UnstyledButton)(
    ({ theme }) => `
    &:focus-visible {
        outline: 1px solid ${theme.vars.palette.stroke.base};
        outline-offset: 2px;
        border-radius: 2px;
    }
    &:active {
        outline: 1px solid ${theme.vars.palette.stroke.faint};
        outline-offset: 1px;
        border-radius: 2px;
    }
`,
);
