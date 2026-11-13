import type { LockerItemType } from "@/types";
import {
    Briefcase01Icon,
    ContactBookIcon,
    File01Icon,
    File02Icon,
    FileUploadIcon,
    Image01Icon,
    LockPasswordIcon,
    NoteIcon,
    Presentation01Icon,
    Table01Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import type { ComponentProps } from "react";

interface LockerIconConfig {
    icon: ComponentProps<typeof HugeiconsIcon>["icon"];
    color: string;
    backgroundColor: string;
}

const itemTypeIconConfigs: Record<LockerItemType, LockerIconConfig> = {
    note: {
        icon: NoteIcon,
        color: "#f08a1e",
        backgroundColor: "rgba(255, 152, 0, 0.06)",
    },
    physicalRecord: {
        icon: Briefcase01Icon,
        color: "#9610d6",
        backgroundColor: "rgba(156, 39, 176, 0.06)",
    },
    accountCredential: {
        icon: LockPasswordIcon,
        color: "#1071ff",
        backgroundColor: "rgba(16, 113, 255, 0.06)",
    },
    emergencyContact: {
        icon: ContactBookIcon,
        color: "rgba(244, 67, 54, 1)",
        backgroundColor: "rgba(244, 67, 54, 0.06)",
    },
    file: { icon: File02Icon, color: "#666666", backgroundColor: "#FAFAFA" },
};

const fileIconConfigs: Record<string, LockerIconConfig> = {
    pdf: {
        icon: File01Icon,
        color: "#f63a3a",
        backgroundColor: "rgba(255, 58, 58, 0.06)",
    },
    image: {
        icon: Image01Icon,
        color: "#08c225",
        backgroundColor: "rgba(8, 194, 37, 0.06)",
    },
    presentation: {
        icon: Presentation01Icon,
        color: "#1071ff",
        backgroundColor: "rgba(16, 113, 255, 0.06)",
    },
    spreadsheet: {
        icon: Table01Icon,
        color: "#08c225",
        backgroundColor: "#E8F5E9",
    },
    default: itemTypeIconConfigs.file,
};

export const createDocumentIconConfig: LockerIconConfig = {
    icon: FileUploadIcon,
    color: "#1071ff",
    backgroundColor: "rgba(16, 113, 255, 0.06)",
};

export const lockerItemIconConfig = (
    type: LockerItemType,
    fileName?: string,
): LockerIconConfig => {
    if (type !== "file") {
        return itemTypeIconConfigs[type];
    }

    const ext = fileName?.split(".").pop()?.toLowerCase() ?? "";
    if (ext === "pdf") {
        return fileIconConfigs.pdf!;
    }
    if (["jpg", "jpeg", "png", "heic"].includes(ext)) {
        return fileIconConfigs.image!;
    }
    if (ext === "pptx") {
        return fileIconConfigs.presentation!;
    }
    if (ext === "xlsx") {
        return fileIconConfigs.spreadsheet!;
    }

    return fileIconConfigs.default!;
};

export const lockerItemIcon = (
    type: LockerItemType,
    options?: { fileName?: string; size?: number; strokeWidth?: number },
) => {
    const { icon, color } = lockerItemIconConfig(type, options?.fileName);
    return (
        <HugeiconsIcon
            icon={icon}
            size={options?.size ?? 20}
            strokeWidth={options?.strokeWidth ?? 1.9}
            color={color}
        />
    );
};
