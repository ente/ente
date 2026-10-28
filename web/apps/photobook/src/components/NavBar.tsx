"use client";

import { Box } from "@mui/material";
import { useEffect, useState } from "react";
import { CloseIcon, MenuIcon } from "./icons";

const mobileNavQuery = "(max-width: 640px)";

interface NavItem {
    label: string;
    href: string;
}

const navItems: NavItem[] = [
    { label: "Home", href: "https://ente.com/" },
    { label: "About", href: "https://ente.com/about" },
    { label: "Blog", href: "https://ente.com/blog" },
    { label: "Download", href: "https://ente.com/download" },
];

export default function NavBar() {
    const [isMobileNav, setIsMobileNav] = useState(
        () =>
            typeof window !== "undefined" &&
            window.matchMedia(mobileNavQuery).matches,
    );
    const [isNavOpen, setIsNavOpen] = useState(false);

    useEffect(() => {
        const mql = window.matchMedia(mobileNavQuery);
        const handler = (e: MediaQueryListEvent) => setIsMobileNav(e.matches);
        setIsMobileNav(mql.matches);
        mql.addEventListener("change", handler);
        return () => mql.removeEventListener("change", handler);
    }, []);

    useEffect(() => {
        if (!isMobileNav) setIsNavOpen(false);
    }, [isMobileNav]);

    useEffect(() => {
        if (!isNavOpen) return;
        const handler = (e: KeyboardEvent) => {
            if (e.key === "Escape") setIsNavOpen(false);
        };
        window.addEventListener("keydown", handler);
        return () => window.removeEventListener("keydown", handler);
    }, [isNavOpen]);

    const closeNav = () => {
        if (isMobileNav) setIsNavOpen(false);
    };

    return (
        <Box
            component="header"
            sx={{
                position: "fixed",
                top: 0,
                left: 0,
                right: 0,
                zIndex: 50,
                p: { xs: "16px", sm: "28px 24px" },
            }}
        >
            <Box
                sx={{
                    display: "flex",
                    alignItems: isNavOpen ? "stretch" : "center",
                    flexDirection: isNavOpen ? "column" : "row",
                    justifyContent: "space-between",
                    gap: isNavOpen ? "14px" : "18px",
                    padding: isNavOpen ? "18px" : "14px 18px",
                    border: "1px solid rgba(21, 21, 21, 0.08)",
                    borderRadius: isNavOpen ? "28px" : "999px",
                    background: "rgba(255, 255, 255, 0.76)",
                    backdropFilter: "blur(28px)",
                    boxShadow: "0 20px 48px rgba(18, 18, 18, 0.07)",
                    maxWidth: 1100,
                    mx: "auto",
                    animation:
                        "navSlideIn 0.45s cubic-bezier(0.22, 1, 0.36, 1)",
                    "@keyframes navSlideIn": {
                        from: { opacity: 0, transform: "translateY(-16px)" },
                        to: { opacity: 1, transform: "translateY(0)" },
                    },
                }}
            >
                <Box
                    sx={{
                        display: "flex",
                        alignItems: "center",
                        justifyContent: isMobileNav
                            ? "space-between"
                            : "flex-start",
                        width: isMobileNav ? "100%" : "auto",
                        gap: "12px",
                    }}
                >
                    <Box
                        component="a"
                        href="https://ente.com/"
                        target="_blank"
                        rel="noopener"
                        onClick={closeNav}
                        sx={{
                            display: "inline-flex",
                            alignItems: "center",
                            ml: isMobileNav ? 0 : "10px",
                            minHeight: isMobileNav ? 40 : "auto",
                            cursor: "pointer",
                            textDecoration: "none",
                        }}
                    >
                        <Box
                            component="img"
                            alt="Ente"
                            src="/ente-branding.svg"
                            sx={{
                                display: "block",
                                width: "auto",
                                height: { xs: "21.6px", sm: "25.2px" },
                            }}
                        />
                    </Box>

                    {isMobileNav && (
                        <Box
                            component="button"
                            onClick={() => setIsNavOpen((c) => !c)}
                            aria-label={
                                isNavOpen
                                    ? "Close navigation menu"
                                    : "Open navigation menu"
                            }
                            aria-expanded={isNavOpen}
                            sx={{
                                display: "inline-flex",
                                width: 44,
                                minHeight: 44,
                                p: 0,
                                border: "1px solid rgba(21, 21, 21, 0.08)",
                                borderRadius: "14px",
                                background: "rgba(255, 255, 255, 0.62)",
                                color: "rgba(21, 21, 21, 0.84)",
                                alignItems: "center",
                                justifyContent: "center",
                                cursor: "pointer",
                                transition:
                                    "transform 220ms ease, border-color 220ms ease, background 220ms ease",
                                "&:hover": {
                                    transform: "translateY(-1px)",
                                    borderColor: "rgba(21, 21, 21, 0.14)",
                                    background: "rgba(255, 255, 255, 0.78)",
                                },
                            }}
                        >
                            {isNavOpen ? <CloseIcon /> : <MenuIcon />}
                        </Box>
                    )}
                </Box>

                {(!isMobileNav || isNavOpen) && (
                    <Box
                        component="nav"
                        aria-label="Primary"
                        sx={{
                            display: isMobileNav ? "grid" : "flex",
                            gridTemplateColumns: isMobileNav
                                ? "1fr"
                                : undefined,
                            flexWrap: "wrap",
                            justifyContent: isMobileNav
                                ? undefined
                                : "flex-end",
                            gap: isMobileNav ? "8px" : "10px",
                            width: isMobileNav ? "100%" : "auto",
                        }}
                    >
                        {navItems.map((item) => (
                            <Box
                                key={item.label}
                                component="a"
                                href={item.href}
                                target="_blank"
                                rel="noopener"
                                onClick={closeNav}
                                sx={{
                                    display: "inline-flex",
                                    alignItems: "center",
                                    justifyContent: isMobileNav
                                        ? "flex-start"
                                        : "center",
                                    minHeight: isMobileNav ? 44 : 42,
                                    px: isMobileNav ? "16px" : "18px",
                                    borderRadius: "999px",
                                    border: "1px solid",
                                    borderColor: isMobileNav
                                        ? "rgba(21, 21, 21, 0.06)"
                                        : "transparent",
                                    background: isMobileNav
                                        ? "rgba(255, 255, 255, 0.52)"
                                        : "transparent",
                                    color: "rgba(21, 21, 21, 0.76)",
                                    fontFamily: "var(--font-inter), sans-serif",
                                    fontSize: "0.92rem",
                                    fontWeight: 500,
                                    letterSpacing: 0,
                                    textDecoration: "none",
                                    textAlign: isMobileNav ? "left" : "center",
                                    transition:
                                        "transform 220ms ease, border-color 220ms ease, background 220ms ease, color 220ms ease",
                                    "&:hover": {
                                        transform: "translateY(-1px)",
                                        borderColor: "rgba(21, 21, 21, 0.08)",
                                        background: "rgba(255, 255, 255, 0.65)",
                                        color: "#151515",
                                    },
                                }}
                            >
                                {item.label}
                            </Box>
                        ))}
                    </Box>
                )}
            </Box>
        </Box>
    );
}
