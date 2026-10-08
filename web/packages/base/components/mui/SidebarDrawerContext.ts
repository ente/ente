import { createContext } from "react";

export const SidebarPanelContext = createContext<
    (() => HTMLElement | null) | undefined
>(undefined);

export const SidebarDrawerDepthContext = createContext(0);
