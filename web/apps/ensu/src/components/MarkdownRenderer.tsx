import {
    handleExternalLinkClick,
    safeExternalUrl,
} from "@/services/external-links";
import { Copy01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, IconButton } from "@mui/material";
import { useBaseContext } from "ente-base/context";
import React, { useState } from "react";
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
    const [copyResult, setCopyResult] = useState<{
        text: string;
        message: string;
    }>();
    const copyStatus = copyResult?.text === codeText ? copyResult.message : "";
    const handleCopy = () => {
        void navigator.clipboard.writeText(codeText).then(
            () => setCopyResult({ text: codeText, message: "Copied" }),
            () => setCopyResult({ text: codeText, message: "Could not copy" }),
        );
    };

    return (
        <Box className="markdown-code-block">
            <Box
                sx={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "flex-end",
                    gap: 1,
                    px: "8px",
                    py: "4px",
                }}
            >
                <Box component="span" role="status" sx={{ fontSize: "12px" }}>
                    {copyStatus}
                </Box>
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
            <Box component="pre" {...rest}>
                {children}
            </Box>
        </Box>
    );
};

type AnchorProps = React.ComponentPropsWithoutRef<"a"> & { node?: unknown };

const ExternalLink = ({
    node: _node,
    href,
    children,
    ...rest
}: AnchorProps) => {
    const { showMiniDialog } = useBaseContext();
    const safeHref = safeExternalUrl(href);
    if (!safeHref) return <>{children}</>;

    return (
        <a
            {...rest}
            href={safeHref}
            target="_blank"
            rel="noopener noreferrer"
            onClick={(event) => handleExternalLinkClick(event, showMiniDialog)}
        >
            {children}
        </a>
    );
};

type TableProps = React.ComponentPropsWithoutRef<"table"> & { node?: unknown };

const MarkdownTable = ({ node: _node, ...props }: TableProps) => (
    <div
        className="markdown-table"
        tabIndex={0}
        role="region"
        aria-label="Table"
    >
        <table {...props} />
    </div>
);

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
                components={{
                    pre: CodeBlock,
                    a: ExternalLink,
                    table: MarkdownTable,
                }}
            >
                {content}
            </ReactMarkdown>
        </div>
    );
};
