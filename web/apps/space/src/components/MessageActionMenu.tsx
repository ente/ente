import { Box, MenuItem, MenuList } from "@mui/material";
import React from "react";
import {
    spaceDanger,
    spaceMenuBackground,
    spaceMenuHover,
    spaceText,
} from "styles/colors";
import { spaceTouchTargetSize } from "styles/touch-targets";

export const ReplyIcon: React.FC = () => (
    <svg
        width="12"
        height="9"
        viewBox="0 0 12 9"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            fillRule="evenodd"
            clipRule="evenodd"
            d="M4.5241 0.242677C4.62341 0.34442 4.67919 0.482337 4.67919 0.626134C4.67919 0.76993 4.62341 0.907847 4.5241 1.00959L1.89369 3.70102H7.68483C8.3587 3.70102 9.35854 3.9036 10.2042 4.52653C11.0775 5.17045 11.7507 6.23762 11.7507 7.86116C11.7507 8.00507 11.6948 8.14309 11.5953 8.24485C11.4959 8.34661 11.361 8.40378 11.2203 8.40378C11.0797 8.40378 10.9448 8.34661 10.8453 8.24485C10.7459 8.14309 10.69 8.00507 10.69 7.86116C10.69 6.59069 10.1844 5.84982 9.58481 5.40776C8.95761 4.94544 8.18899 4.78627 7.68483 4.78627H1.89369L4.5241 7.4777C4.5762 7.52738 4.61799 7.58728 4.64698 7.65384C4.67597 7.72041 4.69155 7.79226 4.69281 7.86512C4.69406 7.93798 4.68096 8.01035 4.65429 8.07791C4.62762 8.14548 4.58792 8.20686 4.53756 8.25839C4.4872 8.30991 4.42722 8.35053 4.36118 8.37782C4.29515 8.40512 4.22442 8.41852 4.15321 8.41723C4.082 8.41595 4.01178 8.4 3.94673 8.37034C3.88167 8.34068 3.82313 8.29792 3.77457 8.24461L0.23908 4.6271C0.139767 4.52536 0.0839844 4.38744 0.0839844 4.24364C0.0839844 4.09985 0.139767 3.96193 0.23908 3.86019L3.77457 0.242677C3.87401 0.141061 4.0088 0.0839844 4.14934 0.0839844C4.28987 0.0839844 4.42466 0.141061 4.5241 0.242677Z"
            fill="currentColor"
            stroke="currentColor"
            strokeWidth="0.166667"
        />
    </svg>
);

export const DeleteIcon: React.FC = () => (
    <svg
        width="13"
        height="15"
        viewBox="0 0 13 15"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M11.5 2.83203L11.0869 9.51543C10.9813 11.223 10.9285 12.0768 10.5005 12.6906C10.2889 12.9941 10.0165 13.2502 9.70047 13.4427C9.0614 13.832 8.206 13.832 6.49513 13.832C4.78208 13.832 3.92553 13.832 3.28603 13.442C2.96987 13.2492 2.69733 12.9926 2.48579 12.6886C2.05792 12.0738 2.0063 11.2188 1.90307 9.50883L1.5 2.83203M0.5 2.83333H12.5M9.2038 2.83333L8.74873 1.89449C8.4464 1.27084 8.2952 0.959013 8.03447 0.76454C7.97667 0.7214 7.9154 0.683027 7.85133 0.6498C7.5626 0.5 7.21607 0.5 6.523 0.5C5.81253 0.5 5.45733 0.5 5.16379 0.65608C5.09873 0.690673 5.03665 0.7306 4.97819 0.775447C4.71443 0.9778 4.56709 1.30103 4.27241 1.94751L3.86861 2.83333M4.83203 10.166V6.16602M8.16797 10.166V6.16602"
            stroke="currentColor"
            strokeLinecap="round"
        />
    </svg>
);

export const CopyIcon: React.FC = () => (
    <svg
        width="14"
        height="14"
        viewBox="0 0 14 14"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M4.5 4.5V2.5C4.5 1.39543 5.39543 0.5 6.5 0.5H11.5C12.6046 0.5 13.5 1.39543 13.5 2.5V7.5C13.5 8.60457 12.6046 9.5 11.5 9.5H9.5M2.5 4.5H7.5C8.60457 4.5 9.5 5.39543 9.5 6.5V11.5C9.5 12.6046 8.60457 13.5 7.5 13.5H2.5C1.39543 13.5 0.5 12.6046 0.5 11.5V6.5C0.5 5.39543 1.39543 4.5 2.5 4.5Z"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
    </svg>
);

export const MessageActionMenuItem: React.FC<{
    icon: React.ReactNode;
    label: string;
    onClick: () => void;
    tone?: "default" | "danger";
}> = ({ icon, label, onClick, tone = "default" }) => (
    <MenuItem
        disableRipple
        onClick={onClick}
        sx={{
            WebkitTapHighlightColor: "transparent",
            borderRadius: "12px",
            color: tone == "danger" ? spaceDanger : spaceText,
            gap: "8px",
            minHeight: spaceTouchTargetSize,
            outline: 0,
            px: "8px",
            py: "7px",
            "&.Mui-focusVisible": {
                bgcolor:
                    tone == "danger"
                        ? "rgba(246, 58, 58, 0.14)"
                        : spaceMenuHover,
                outline: 0,
            },
            "&:focus": { outline: 0 },
            "&:focus-visible": { outline: 0 },
            "&:hover": {
                bgcolor:
                    tone == "danger"
                        ? "rgba(246, 58, 58, 0.14)"
                        : spaceMenuHover,
            },
        }}
    >
        {icon}
        <Box
            sx={{
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 13,
                fontWeight: 650,
                lineHeight: "18px",
            }}
        >
            {label}
        </Box>
    </MenuItem>
);

const messageActionMenuListSx = {
    alignSelf: "flex-start",
    bgcolor: spaceMenuBackground,
    borderRadius: "16px",
    boxShadow:
        "0 0 0 1px rgba(255, 255, 255, 0.08), 0 8px 24px rgba(0, 0, 0, 0.32)",
    minWidth: 132,
    outline: 0,
    p: "4px",
    width: "max-content",
    "&:focus": { outline: 0 },
    "&:focus-visible": { outline: 0 },
};

export const MessageActionMenuList: React.FC<
    React.ComponentProps<typeof MenuList>
> = (props) => (
    <MenuList {...props} sx={messageActionMenuListSx} variant="menu" />
);
