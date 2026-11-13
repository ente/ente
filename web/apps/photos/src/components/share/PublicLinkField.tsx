import { Copy01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import DoneIcon from "@mui/icons-material/Done";
import { IconButton, Stack, Tooltip, Typography } from "@mui/material";
import { useClipboardCopy } from "ente-base/components/utils/hooks";
import { t } from "i18next";

export const PublicLinkField = ({
    url,
    isLoading = false,
    error = false,
    variant,
}: {
    url: string | undefined;
    isLoading?: boolean;
    error?: boolean;
    variant?: "dialog";
}) => (
    <Stack
        direction="row"
        sx={(theme) => ({
            alignItems: "center",
            gap: "8px",
            height: 52,
            px: "16px",
            borderRadius: "16px",
            bgcolor: "fill.faint",
            ...theme.applyStyles("light", { bgcolor: "#F4F4F4" }),
            ...(variant == "dialog" && {
                bgcolor: "background.paper",
                ...theme.applyStyles("light", { bgcolor: "background.paper" }),
                "& svg": { width: 20, height: 20 },
            }),
        })}
    >
        <Typography
            component="span"
            title={url}
            aria-live="polite"
            sx={{
                flex: 1,
                minWidth: 0,
                fontSize: 14,
                fontWeight: 500,
                lineHeight: "20px",
                letterSpacing: 0,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
            }}
        >
            {url?.replace(/^https?:\/\//, "") ??
                (error ? t("generic_error") : isLoading ? t("loading") : null)}
        </Typography>
        <CopyLinkButton key={url ?? "pending"} url={url} />
    </Stack>
);

const CopyLinkButton = ({ url }: { url: string | undefined }) => {
    const [copied, copy] = useClipboardCopy(url ?? "");
    const label = t(copied ? "copied" : "copy_link");
    return (
        <Tooltip title={label}>
            <span>
                <IconButton
                    aria-label={label}
                    disabled={!url}
                    onClick={copy}
                    sx={{
                        width: 36,
                        height: 36,
                        p: 0,
                        mr: "-6px",
                        borderRadius: "8px",
                    }}
                >
                    {copied ? (
                        <DoneIcon sx={{ fontSize: 24, color: "accent.main" }} />
                    ) : (
                        <HugeiconsIcon
                            icon={Copy01Icon}
                            size={24}
                            strokeWidth={1.5}
                        />
                    )}
                </IconButton>
            </span>
        </Tooltip>
    );
};
