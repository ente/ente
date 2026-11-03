import type { VoiceView } from "@/hooks/use-voice-input";
import { Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, IconButton, LinearProgress, Typography } from "@mui/material";

export function VoiceInputControls({
    view,
    onCancel,
}: {
    view: VoiceView;
    onCancel: () => void;
}) {
    const listening = view.phase === "listening" || view.phase === "countdown";
    return (
        <Box sx={{ px: 1, py: 1, width: "100%" }}>
            <Box sx={{ display: "flex", alignItems: "center", gap: 0.5 }}>
                <IconButton
                    aria-label="Discard voice input"
                    onClick={onCancel}
                    disabled={view.phase === "cancelling"}
                >
                    <HugeiconsIcon
                        icon={Cancel01Icon}
                        size={24}
                        strokeWidth={2}
                    />
                </IconButton>
                <Typography variant="small" role="status" sx={{ flex: 1 }}>
                    {view.status}
                </Typography>
                {listening && (
                    <Box
                        aria-hidden
                        sx={{
                            display: "flex",
                            gap: "2px",
                            alignItems: "center",
                            height: 28,
                        }}
                    >
                        {view.levels.map((level, i) => (
                            <Box
                                key={i}
                                sx={{
                                    width: 3,
                                    borderRadius: 1,
                                    height: Math.max(3, Math.sqrt(level) * 28),
                                    bgcolor: "accent.main",
                                }}
                            />
                        ))}
                    </Box>
                )}
            </Box>
            {view.phase === "preparing" && (
                <LinearProgress
                    variant={
                        view.percent !== undefined && view.percent < 100
                            ? "determinate"
                            : "indeterminate"
                    }
                    value={view.percent}
                    sx={{ my: 1 }}
                />
            )}
        </Box>
    );
}
