import {
    Paper,
    Table,
    TableBody,
    TableCell,
    TableContainer,
    TableHead,
    TableRow,
} from "@mui/material";
import React, { useEffect, useState } from "react";
import { getStorageBonuses, type StorageBonus } from "../services/admin-user";
import { useInitialStaffSession } from "../services/session";
import { dateFromMicroseconds, formatBytesToGB } from "../utils";
import { StatusBadge } from "./StatusBadge";

export const StorageBonusTableComponent: React.FC = () => {
    const [storageBonuses, setStorageBonuses] = useState<StorageBonus[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const session = useInitialStaffSession();

    useEffect(() => {
        const fetchData = async () => {
            try {
                setStorageBonuses(await getStorageBonuses(session));
            } catch (error) {
                console.error("Error fetching bonus data:", error);
                setError("No bonus data");
            } finally {
                setLoading(false);
            }
        };

        fetchData().catch((error: unknown) =>
            console.error("Fetch data error:", error),
        );
    }, [session]);

    if (loading) {
        return <p>Loading...</p>;
    }

    if (error) {
        return <p>Error: {error}</p>;
    }

    if (storageBonuses.length === 0) {
        return <p>No bonus data available</p>;
    }

    return (
        <TableContainer
            component={Paper}
            sx={{ mt: "20px", mb: "20px", bgcolor: "#F1F1F3" }}
        >
            <Table aria-label="storage-bonus-table">
                <TableHead>
                    <TableRow>
                        <TableCell>
                            <b>Storage</b>
                        </TableCell>
                        <TableCell>
                            <b>Type</b>
                        </TableCell>
                        <TableCell>
                            <b>Created At</b>
                        </TableCell>
                        <TableCell>
                            <b>Valid Till</b>
                        </TableCell>
                        <TableCell>
                            <b>Is Revoked</b>
                        </TableCell>
                    </TableRow>
                </TableHead>
                <TableBody>
                    {storageBonuses.map((bonus, index) => (
                        <TableRow key={index}>
                            <TableCell>
                                {formatBytesToGB(bonus.storage)}
                            </TableCell>
                            <TableCell>{bonus.type}</TableCell>
                            <TableCell>
                                {formatCreatedAt(bonus.createdAt)}
                            </TableCell>
                            <TableCell>
                                {formatValidTill(bonus.validTill)}
                            </TableCell>
                            <TableCell>
                                <StatusBadge highlighted={bonus.isRevoked}>
                                    {bonus.isRevoked ? "Yes" : "No"}
                                </StatusBadge>
                            </TableCell>
                        </TableRow>
                    ))}
                </TableBody>
            </Table>
        </TableContainer>
    );
};

const formatCreatedAt = (createdAt: number): string =>
    dateFromMicroseconds(createdAt).toLocaleDateString();

const formatValidTill = (validTill: number): string => {
    if (validTill === 0) {
        return "Forever";
    }
    return dateFromMicroseconds(validTill).toLocaleDateString();
};
