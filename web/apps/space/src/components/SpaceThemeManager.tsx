import React, { useEffect } from "react";
import { useSpaceAppState } from "state/spaceAppState";

interface SpaceThemeManagerProps {
    children: React.ReactNode;
}

const lightColors = {
    bg: "#FAFAFA",
    homeBg: "#F5F5F7",
    profileBg: "#FFFFFF",
    rowBg: "#FFFFFF",
    rowHoverBg: "rgba(0, 0, 0, 0.025)",
    feedCardBg: "#FFFFFF",
    feedActionBg: "#F7F7F7",
    feedActionHoverBg: "#EFEFEF",
    feedSkeletonBg: "#E6E6E6",
    text: "#000000",
    textSecondary: "#6B6B6B",
    textMuted: "#8E8E93",
    danger: "#F63A3A",
    duckyFilter: "none",
    spaceLogoFilter: "none",
};

const darkColors = {
    bg: "#161616",         
    homeBg: "#161616",  
    profileBg: "#161616",  
    rowBg: "#212121",    
    rowHoverBg: "#292929",
    feedCardBg: "#212121", 
    feedActionBg: "#141414",
    feedActionHoverBg: "#292929",
    feedSkeletonBg: "#0A0A0A",
    text: "#FFFFFF",
    textSecondary: "#E5E5E5",  
    textMuted: "#CCCCCC",      
    danger: "#F63A3A",
    duckyFilter: "invert(1) brightness(0.9)",
    spaceLogoFilter: "invert(1)",
};

const applyColors = (colors: typeof lightColors) => {
    const root = document.documentElement;
    root.style.setProperty("--bg-color", colors.bg);
    root.style.setProperty("--home-bg-color", colors.homeBg);
    root.style.setProperty("--profile-bg-color", colors.profileBg);
    root.style.setProperty("--row-bg-color", colors.rowBg);
    root.style.setProperty("--row-hover-bg-color", colors.rowHoverBg);
    root.style.setProperty("--feed-card-bg", colors.feedCardBg);
    root.style.setProperty("--feed-action-bg", colors.feedActionBg);
    root.style.setProperty("--feed-action-hover-bg", colors.feedActionHoverBg);
    root.style.setProperty("--feed-skeleton-bg", colors.feedSkeletonBg);
    root.style.setProperty("--text-color", colors.text);
    root.style.setProperty("--text-secondary", colors.textSecondary);
    root.style.setProperty("--text-muted", colors.textMuted);
    root.style.setProperty("--danger-color", colors.danger);
    root.style.setProperty("--ducky-filter", colors.duckyFilter);
    root.style.setProperty("--space-logo-filter", colors.spaceLogoFilter);
};

export const SpaceThemeManager: React.FC<SpaceThemeManagerProps> = ({
    children,
}) => {
    const { isDarkMode, profile } = useSpaceAppState();

    useEffect(() => {
        const shouldApplyDark = isDarkMode && profile != null;
        const root = document.documentElement;

        if (shouldApplyDark) {
            root.classList.add("dark-mode");
            applyColors(darkColors);
            document.body.style.backgroundColor = darkColors.bg;
            document.body.style.color = darkColors.text;
        } else {
            root.classList.remove("dark-mode");
            applyColors(lightColors);
            document.body.style.backgroundColor = lightColors.bg;
            document.body.style.color = lightColors.text;
        }
    }, [isDarkMode, profile]);

    return <>{children}</>;
};
