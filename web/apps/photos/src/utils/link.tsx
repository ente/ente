import { Link } from "@mui/material";

export const externalLink = (href: string) => (
    <Link href={href} target="_blank" rel="noopener" />
);
