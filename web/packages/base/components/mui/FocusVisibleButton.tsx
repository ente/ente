import { Button, styled, type ButtonProps } from "@mui/material";
import type {} from "ente-base/components/utils/mui-theme";
import React from "react";

export const RippleDisabledButton: React.FC<ButtonProps> = (props) => (
    <Button disableRipple {...props} />
);

/**
 * A MUI {@link Button} that shows a keyboard focus indicator (e.g. when the
 * user tabs to it) and also an affordance to indicate when it is activated.
 */
export const FocusVisibleButton = styled(RippleDisabledButton)(
    ({ theme }) => `
    &.Mui-focusVisible {
        outline: 1px solid ${theme.vars.palette.stroke.base};
        outline-offset: 2px;
    }
    &:active {
        outline: 1px solid ${theme.vars.palette.stroke.faint};
        outline-offset: 1px;
    }
`,
);
