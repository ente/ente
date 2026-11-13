import {
    Box,
    Button,
    CircularProgress,
    Paper,
    Table,
    TableBody,
    TableCell,
    TableContainer,
    TableHead,
    TableRow,
} from "@mui/material";
import React, { useEffect, useState } from "react";
import { getFamilyMembers, type FamilyMember } from "../services/admin-user";
import { useInitialStaffSession } from "../services/session";
import { formatBytesToGB } from "../utils";
import { CloseFamily } from "./CloseFamily";
import { StatusBadge } from "./StatusBadge";

export const FamilyTable: React.FC = () => {
    const [familyMembers, setFamilyMembers] = useState<FamilyMember[]>([]);
    const [closeFamilyOpen, setCloseFamilyOpen] = useState(false);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const session = useInitialStaffSession();

    useEffect(() => {
        const fetchData = async () => {
            try {
                setFamilyMembers(await getFamilyMembers(session));
            } catch (error) {
                console.error("Error fetching family data:", error);
                setError("No family data");
            } finally {
                setLoading(false);
            }
        };

        fetchData().catch((error: unknown) =>
            console.error("Fetch data error:", error),
        );
    }, [session]);

    const handleOpenCloseFamily = () => {
        setCloseFamilyOpen(true);
    };

    const handleCloseFamilyDialog = () => {
        setCloseFamilyOpen(false);
    };

    if (loading) {
        return <CircularProgress />;
    }

    if (error) {
        return <div>Error: {error}</div>;
    }

    if (familyMembers.length === 0) {
        return <div>No family data available</div>;
    }

    return (
        <>
            <TableContainer
                component={Paper}
                sx={{ mt: "20px", bgcolor: "#F1F1F3" }}
            >
                <Table aria-label="family-table">
                    <TableHead>
                        <TableRow>
                            <TableCell>
                                <b>ID</b>
                            </TableCell>
                            <TableCell>
                                <b>User</b>
                            </TableCell>
                            <TableCell>
                                <b>Status</b>
                            </TableCell>
                            <TableCell>
                                <b>Usage</b>
                            </TableCell>
                            <TableCell>
                                <b>Quota</b>
                            </TableCell>
                        </TableRow>
                    </TableHead>
                    <TableBody>
                        {familyMembers.map((member) => (
                            <TableRow key={member.id}>
                                <TableCell>{member.id}</TableCell>
                                <TableCell>{member.email}</TableCell>
                                <TableCell>
                                    <StatusBadge
                                        highlighted={member.status === "SELF"}
                                        tone="success"
                                    >
                                        {member.status === "SELF"
                                            ? "ADMIN"
                                            : member.status}
                                    </StatusBadge>
                                </TableCell>
                                <TableCell>
                                    {member.usage === undefined
                                        ? "NA"
                                        : formatBytesToGB(member.usage)}
                                </TableCell>
                                <TableCell>
                                    {member.status !== "SELF"
                                        ? (member.storageLimit &&
                                              formatBytesToGB(
                                                  member.storageLimit,
                                              )) ||
                                          "NA"
                                        : ""}
                                </TableCell>
                            </TableRow>
                        ))}
                    </TableBody>
                </Table>
            </TableContainer>
            <Box sx={{ mt: "20px" }}>
                <Button
                    variant="contained"
                    color="error"
                    onClick={handleOpenCloseFamily}
                >
                    Close Family
                </Button>
            </Box>

            {closeFamilyOpen && (
                <CloseFamily
                    open={closeFamilyOpen}
                    handleClose={handleCloseFamilyDialog}
                    handleCloseFamily={handleCloseFamilyDialog}
                />
            )}
        </>
    );
};
