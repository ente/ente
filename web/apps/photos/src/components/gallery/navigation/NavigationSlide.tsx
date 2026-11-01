import { Box } from "@mui/material";
import type { PropsWithChildren } from "react";
import {
    navigationMotion,
    useNavigationContentMotion,
} from "./use-navigation-content-motion";

export const NavigationSlide: React.FC<
    PropsWithChildren<{
        open: boolean;
        width: number | { xs: number; sm: number };
        reduceMotion: boolean;
        rail?: boolean;
        disabled?: boolean;
    }>
> = ({ open, width, reduceMotion, rail, disabled = false, children }) => {
    const positionRef = useNavigationContentMotion(
        disabled ? "disabled" : open,
        reduceMotion,
    );
    return (
        <Box
            ref={disabled ? null : positionRef}
            inert={!disabled && !open}
            sx={
                disabled
                    ? { display: "contents" }
                    : {
                          position: "relative",
                          flexShrink: 0,
                          width: open ? width : 0,
                          height: "100%",
                          pointerEvents: open ? undefined : "none",
                          zIndex: rail ? 2 : 1,
                      }
            }
        >
            <Box
                sx={
                    disabled
                        ? { display: "contents" }
                        : {
                              position: "absolute",
                              inset: "0 auto 0 0",
                              width,
                              overflow: "clip",
                          }
                }
            >
                <Box
                    sx={
                        disabled
                            ? { display: "contents" }
                            : {
                                  height: "100%",
                                  transform:
                                      open || reduceMotion
                                          ? "translateX(0)"
                                          : "translateX(-100%)",
                                  opacity: open ? 1 : 0,
                                  transition: reduceMotion
                                      ? `opacity ${navigationMotion.fadeDuration}ms ${navigationMotion.easing}`
                                      : `transform ${navigationMotion.duration}ms ${navigationMotion.easing}, opacity ${navigationMotion.fadeDuration}ms ${navigationMotion.easing}`,
                              }
                    }
                >
                    {children}
                </Box>
            </Box>
        </Box>
    );
};
