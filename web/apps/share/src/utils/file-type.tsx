import {
    Briefcase01Icon,
    ContactBookIcon,
    File02Icon,
    Image01Icon,
    LockPasswordIcon,
    NoteIcon,
    VideoReplayIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import React from "react";

enum LockerInfoType {
    Note = "note",
    PhysicalRecord = "physicalRecord",
    AccountCredential = "accountCredential",
    EmergencyContact = "emergencyContact",
}

interface LockerIconInfo {
    icon: React.ReactElement;
    backgroundColor: string;
}

interface LockerFileIconOptions {
    lockerType?: string;
    size?: number;
}

const getFileExtension = (fileName: string): string => {
    const lastDot = fileName.lastIndexOf(".");
    if (lastDot === -1 || lastDot === fileName.length - 1) {
        return "";
    }
    return fileName.slice(lastDot + 1).toLowerCase();
};

const isImageExtension = (extension: string): boolean => {
    const imageExtensions = [
        "jpg",
        "jpeg",
        "png",
        "gif",
        "webp",
        "bmp",
        "svg",
        "heic",
        "heif",
        "ico",
        "tiff",
        "tif",
    ];
    return imageExtensions.includes(extension);
};

const isVideoExtension = (extension: string): boolean => {
    const videoExtensions = [
        "mp4",
        "mov",
        "avi",
        "mkv",
        "webm",
        "wmv",
        "flv",
        "m4v",
        "3gp",
        "3g2",
        "ogv",
        "mpg",
        "mpeg",
    ];
    return videoExtensions.includes(extension);
};

const isDocumentExtension = (extension: string): boolean => {
    const documentExtensions = [
        "pdf",
        "doc",
        "docx",
        "xls",
        "xlsx",
        "ppt",
        "pptx",
        "txt",
        "rtf",
        "odt",
        "ods",
        "odp",
        "md",
        "csv",
    ];
    return documentExtensions.includes(extension);
};

export const getLockerFileIcon = (
    fileName: string,
    options: LockerFileIconOptions = {},
): LockerIconInfo => {
    const { lockerType, size = 42 } = options;

    if (lockerType) {
        switch (lockerType as LockerInfoType) {
            case LockerInfoType.Note:
                return {
                    icon: (
                        <HugeiconsIcon
                            icon={NoteIcon}
                            size={size}
                            color="#FF9800"
                        />
                    ),
                    backgroundColor: "#FF98000F",
                };

            case LockerInfoType.EmergencyContact:
                return {
                    icon: (
                        <HugeiconsIcon
                            icon={ContactBookIcon}
                            size={size}
                            color="#F44336"
                        />
                    ),
                    backgroundColor: "#F443360F",
                };

            case LockerInfoType.AccountCredential:
                return {
                    icon: (
                        <HugeiconsIcon
                            icon={LockPasswordIcon}
                            size={size}
                            color="#1071FF"
                        />
                    ),
                    backgroundColor: "#1071FF0F",
                };

            case LockerInfoType.PhysicalRecord:
                return {
                    icon: (
                        <HugeiconsIcon
                            icon={Briefcase01Icon}
                            size={size}
                            color="#9C27B0"
                        />
                    ),
                    backgroundColor: "#9C27B00F",
                };
        }
    }

    const extension = getFileExtension(fileName);

    if (isImageExtension(extension)) {
        return {
            icon: (
                <HugeiconsIcon icon={Image01Icon} size={size} color="#08C225" />
            ),
            backgroundColor: "#08C2250F",
        };
    }

    if (isVideoExtension(extension)) {
        return {
            icon: (
                <HugeiconsIcon
                    icon={VideoReplayIcon}
                    size={size}
                    color="#8A38F5"
                />
            ),
            backgroundColor: "rgba(138, 56, 245, 0.06)",
        };
    }

    if (isDocumentExtension(extension)) {
        return {
            icon: (
                <HugeiconsIcon icon={File02Icon} size={size} color="#FF1A53" />
            ),
            backgroundColor: "rgba(255, 26, 83, 0.06)",
        };
    }

    return {
        icon: <HugeiconsIcon icon={File02Icon} size={size} color="#757575" />,
        backgroundColor: "#FAFAFA",
    };
};
