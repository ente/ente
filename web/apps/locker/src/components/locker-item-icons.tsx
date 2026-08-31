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
        color: "rgba(255, 152, 0, 1)",
        backgroundColor: "rgba(255, 152, 0, 0.06)",
    },
    physicalRecord: {
        icon: Briefcase01Icon,
        color: "rgba(156, 39, 176, 1)",
        backgroundColor: "rgba(156, 39, 176, 0.06)",
    },
    accountCredential: {
        icon: LockPasswordIcon,
        color: "rgba(16, 113, 255, 1)",
        backgroundColor: "rgba(16, 113, 255, 0.06)",
    },
    emergencyContact: {
        icon: ContactBookIcon,
        color: "rgba(244, 67, 54, 1)",
        backgroundColor: "rgba(244, 67, 54, 0.06)",
    },
    file: { icon: File02Icon, color: "#757575", backgroundColor: "#FAFAFA" },
};

const fileIconConfigs: Record<string, LockerIconConfig> = {
    pdf: {
        icon: File01Icon,
        color: "rgba(246, 58, 58, 1)",
        backgroundColor: "rgba(255, 58, 58, 0.06)",
    },
    image: {
        icon: Image01Icon,
        color: "rgba(8, 194, 37, 1)",
        backgroundColor: "rgba(8, 194, 37, 0.06)",
    },
    presentation: {
        icon: Presentation01Icon,
        color: "rgba(16, 113, 255, 1)",
        backgroundColor: "rgba(16, 113, 255, 0.06)",
    },
    spreadsheet: {
        icon: Table01Icon,
        color: "#388E3C",
        backgroundColor: "#E8F5E9",
    },
    default: itemTypeIconConfigs.file,
};

export const createDocumentIconConfig: LockerIconConfig = {
    icon: FileUploadIcon,
    color: "rgba(16, 113, 255, 1)",
    backgroundColor: "rgba(16, 113, 255, 0.06)",
};

export const createDocumentIcon = (size = 20, strokeWidth = 1.9) => (
    <HugeiconsIcon
        icon={createDocumentIconConfig.icon}
        size={size}
        strokeWidth={strokeWidth}
        color={createDocumentIconConfig.color}
    />
);

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
