import type { LockerItemType } from "@/types";
import { t } from "i18next";

export const getRequiredFields = (type: LockerItemType): string[] => {
    switch (type) {
        case "note":
            return ["title", "content"];
        case "accountCredential":
            return ["name", "username", "password"];
        case "physicalRecord":
            return ["name", "location"];
        case "emergencyContact":
            return ["name", "contactDetails"];
        case "file":
            return ["name"];
        default:
            return [];
    }
};

export const typeDisplayName = (type: LockerItemType): string => {
    switch (type) {
        case "note":
            return t("personalNote");
        case "accountCredential":
            return t("secret");
        case "physicalRecord":
            return t("thing");
        case "emergencyContact":
            return t("emergencyContact");
        case "file":
            return t("document");
    }
};
