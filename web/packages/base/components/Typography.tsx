import { styled, Typography } from "@mui/material";

export const EllipsizedTypography = styled(Typography)`
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
`;

export const Ellipsized2LineTypography = styled(Typography)`
    overflow: hidden;
    text-overflow: ellipsis;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    word-break: break-word;
`;
