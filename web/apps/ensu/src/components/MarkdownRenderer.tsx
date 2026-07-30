import { isTauriRuntime } from "@/services/tauri-runtime";
import { Copy01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, IconButton } from "@mui/material";
import React, { useCallback } from "react";
import ReactMarkdown from "react-markdown";
import rehypeKatex from "rehype-katex";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";

interface MarkdownRendererProps {
    content: string;
    className?: string;
}

type PreProps = React.ComponentPropsWithoutRef<"pre"> & { node?: unknown };

const isElementWithChildren = (
    node: React.ReactNode,
): node is React.ReactElement<{ children?: React.ReactNode }> =>
    React.isValidElement(node);

const extractCodeText = (node: React.ReactNode): string => {
    if (node == null) return "";
    if (typeof node === "string") return node;
    if (Array.isArray(node)) {
        return node.map(extractCodeText).join("");
    }
    if (isElementWithChildren(node)) {
        return extractCodeText(node.props.children);
    }
    return "";
};

const CodeBlock = ({ children, node: _node, ...rest }: PreProps) => {
    const codeText = extractCodeText(children).replace(/\n$/, "");

    const handleCopy = useCallback(() => {
        if (
            typeof navigator === "undefined" ||
            typeof document === "undefined"
        ) {
            return;
        }

        const clipboard = navigator.clipboard;
        if (clipboard && typeof clipboard.writeText === "function") {
            void clipboard.writeText(codeText);
            return;
        }

        const textarea = document.createElement("textarea");
        textarea.value = codeText;
        textarea.setAttribute("readonly", "true");
        textarea.style.position = "fixed";
        textarea.style.opacity = "0";
        textarea.style.pointerEvents = "none";
        document.body.appendChild(textarea);
        textarea.select();
        try {
            document.execCommand("copy");
        } catch (_error) {
            // Ignore copy errors for unsupported environments.
        } finally {
            document.body.removeChild(textarea);
        }
    }, [codeText]);

    return (
        <Box className="markdown-code-block" sx={{ position: "relative" }}>
            <Box component="pre" {...rest}>
                {children}
            </Box>
            <Box sx={{ position: "absolute", right: 8, bottom: 8 }}>
                <IconButton
                    aria-label="Copy code"
                    onClick={handleCopy}
                    disableRipple
                    sx={{
                        p: "6px",
                        bgcolor: "fill.faint",
                        opacity: 0.8,
                        borderRadius: "6px",
                        color: "text.base",
                        "&:hover": { opacity: 1, bgcolor: "fill.faint" },
                    }}
                >
                    <HugeiconsIcon
                        icon={Copy01Icon}
                        size={14}
                        strokeWidth={2}
                    />
                </IconButton>
            </Box>
        </Box>
    );
};

const openExternalUrl = async (url: string) => {
    if (isTauriRuntime()) {
        try {
            const { openUrl } = await import("@tauri-apps/plugin-opener");
            await openUrl(url);
            return;
        } catch {
            // Fall back to the browser open path below.
        }
    }

    if (typeof window !== "undefined") {
        const popup = window.open(url, "_blank", "noopener,noreferrer");
        if (!popup) {
            window.location.href = url;
        }
    }
};

const safeExternalUrl = (href: string | undefined) => {
    if (!href) return undefined;
    try {
        const url = new URL(href);
        return ["http:", "https:", "mailto:"].includes(url.protocol)
            ? url.toString()
            : undefined;
    } catch {
        return undefined;
    }
};

type AnchorProps = React.ComponentPropsWithoutRef<"a"> & { node?: unknown };

const ExternalLink = ({
    node: _node,
    href,
    children,
    ...rest
}: AnchorProps) => {
    const safeHref = safeExternalUrl(href);
    if (!safeHref) return <>{children}</>;

    return (
        <a
            {...rest}
            href={safeHref}
            onClick={(e) => {
                e.preventDefault();
                if (safeHref) void openExternalUrl(safeHref);
            }}
        >
            {children}
        </a>
    );
};

export const MarkdownRenderer = ({
    content,
    className,
}: MarkdownRendererProps) => {
    return (
        <div className={className}>
            <ReactMarkdown
                remarkPlugins={[remarkGfm, remarkMath]}
                rehypePlugins={[
                    [rehypeKatex, { strict: false, throwOnError: false }],
                ]}
                components={{ pre: CodeBlock, a: ExternalLink }}
            >
                {content}
            </ReactMarkdown>
        </div>
    );
};
