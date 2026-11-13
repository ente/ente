import ContentCopyIcon from "@mui/icons-material/ContentCopy";
import DoneIcon from "@mui/icons-material/Done";
import { IconButton, Tooltip, type SvgIconProps } from "@mui/material";
import { useClipboardCopy } from "ente-base/components/utils/hooks";
import { t } from "i18next";

interface CopyButtonProps {
    text: string;
    size?: SvgIconProps["fontSize"];
}

export const CopyButton: React.FC<CopyButtonProps> = ({ text, size }) => {
    const [copied, handleClick] = useClipboardCopy(text);

    const Icon = copied ? DoneIcon : ContentCopyIcon;

    return (
        <Tooltip arrow open={copied} title={t("copied")}>
            <IconButton onClick={handleClick} color="secondary">
                <Icon fontSize={size} />
            </IconButton>
        </Tooltip>
    );
};
