import {
    Paper,
    Table,
    TableBody,
    TableCell,
    TableContainer,
    TableHead,
    TableRow,
    TableSortLabel,
} from "@mui/material";
import React, { useEffect, useMemo, useState } from "react";
import { getTokens, type TokenData } from "../services/admin-user";
import { useInitialStaffSession } from "../services/session";
import { dateFromMicroseconds } from "../utils";
import { StatusBadge } from "./StatusBadge";

export const TokensTableComponent: React.FC = () => {
    const [tokens, setTokens] = useState<TokenData[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [order, setOrder] = useState<"asc" | "desc">("desc");
    const [orderBy, setOrderBy] = useState<keyof TokenData>("lastUsedTime");
    const session = useInitialStaffSession();

    useEffect(() => {
        const fetchData = async () => {
            try {
                setTokens(await getTokens(session));
            } catch (error) {
                console.error("Error fetching token data:", error);
                setError("No token data");
            } finally {
                setLoading(false);
            }
        };

        fetchData().catch((error: unknown) =>
            console.error("Fetch data error:", error),
        );
    }, [session]);

    const handleRequestSort = (property: keyof TokenData) => {
        const isAsc = orderBy === property && order === "asc";
        setOrder(isAsc ? "desc" : "asc");
        setOrderBy(property);
    };

    const sortedTokens = useMemo(() => {
        const sortableTokens = [...tokens];
        sortableTokens.sort((a, b) => {
            if (orderBy === "lastUsedTime" || orderBy === "creationTime") {
                return order === "asc"
                    ? a[orderBy] - b[orderBy]
                    : b[orderBy] - a[orderBy];
            }
            return 0;
        });
        return sortableTokens;
    }, [order, orderBy, tokens]);

    if (loading) {
        return <p>Loading...</p>;
    }

    if (error) {
        return <p>Error: {error}</p>;
    }

    if (tokens.length === 0) {
        return <p>No token data available</p>;
    }

    return (
        <TableContainer
            component={Paper}
            sx={{ mt: "20px", mb: "20px", bgcolor: "#F1F1F3" }}
        >
            <Table aria-label="tokens-table">
                <TableHead>
                    <TableRow>
                        <TableCell
                            sortDirection={
                                orderBy === "creationTime" ? order : false
                            }
                        >
                            <TableSortLabel
                                active={orderBy === "creationTime"}
                                direction={
                                    orderBy === "creationTime" ? order : "asc"
                                }
                                onClick={() =>
                                    handleRequestSort("creationTime")
                                }
                            >
                                Created At
                            </TableSortLabel>
                        </TableCell>
                        <TableCell
                            sortDirection={
                                orderBy === "lastUsedTime" ? order : false
                            }
                        >
                            <TableSortLabel
                                active={orderBy === "lastUsedTime"}
                                direction={
                                    orderBy === "lastUsedTime" ? order : "asc"
                                }
                                onClick={() =>
                                    handleRequestSort("lastUsedTime")
                                }
                            >
                                Last Used At
                            </TableSortLabel>
                        </TableCell>
                        <TableCell>
                            <b>User Agent</b>
                        </TableCell>
                        <TableCell>
                            <b>App</b>
                        </TableCell>
                        <TableCell>
                            <b>Is Deleted</b>
                        </TableCell>
                    </TableRow>
                </TableHead>
                <TableBody>
                    {sortedTokens.map((token, index) => (
                        <TableRow key={index}>
                            <TableCell>
                                {formatDate(token.creationTime)}
                            </TableCell>
                            <TableCell>
                                {formatDate(token.lastUsedTime)}
                            </TableCell>
                            <TableCell>{token.ua || "-"}</TableCell>
                            <TableCell>{token.app}</TableCell>
                            <TableCell>
                                <StatusBadge highlighted={token.isDeleted}>
                                    {token.isDeleted ? "Yes" : "No"}
                                </StatusBadge>
                            </TableCell>
                        </TableRow>
                    ))}
                </TableBody>
            </Table>
        </TableContainer>
    );
};

const formatDate = (timestamp: number): string =>
    dateFromMicroseconds(timestamp).toLocaleDateString();
