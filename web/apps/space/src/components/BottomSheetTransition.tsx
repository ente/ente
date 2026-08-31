import Slide from "@mui/material/Slide";
import type { TransitionProps } from "@mui/material/transitions";
import React, { forwardRef } from "react";

const bottomSheetTransitionDurationMs = 225;

export const SpaceBottomSheetTransition = forwardRef(function Transition(
    props: TransitionProps & { children: React.ReactElement },
    ref: React.Ref<unknown>,
) {
    return (
        <Slide
            direction="up"
            ref={ref}
            {...props}
            timeout={bottomSheetTransitionDurationMs}
        />
    );
});
