import type { LockerItemType } from "@/types";
import { t } from "i18next";

export const getRequiredFields = (type: LockerItemType): string[] => {
    switch (type) {
        case "note":
            return ["content"];
        case "accountCredential":
            return ["name"];
        case "physicalRecord":
            return ["name"];
        case "emergencyContact":
            return ["name", "contactDetails"];
        case "file":
            return ["name"];
        default:
            return [];
    }
};

export const itemFormDataForSave = (
    type: LockerItemType,
    formData: Record<string, string>,
): Record<string, string> => {
    const data: Record<string, string> = Object.fromEntries(
        Object.entries(formData)
            .map(
                ([key, value]) =>
                    [
                        key,
                        type === "accountCredential" && key === "password"
                            ? value
                            : value.trim(),
                    ] as const,
            )
            .filter(([, value]) => value),
    );

    if (type === "note" && !data.title) {
        const firstLine = data.content?.split("\n", 1)[0]?.trim() ?? "";
        const title = firstLine.split(/\s+/).slice(0, 5).join(" ");
        data.title =
            title.length <= 40 ? title : `${title.slice(0, 40).trimEnd()}...`;
    }

    return data;
};

export function hasUnsavedItemChanges(
    data: Record<string, string>,
    initialData: Record<string, string>,
    collectionIDs: number[],
    initialCollectionIDs: number[],
    collectionName: string,
): boolean {
    const fields = new Set([...Object.keys(data), ...Object.keys(initialData)]);
    const collections = new Set(collectionIDs);
    const initialCollections = new Set(initialCollectionIDs);

    const hasCollectionDraft = collectionName !== "";
    const hasFieldChanges = [...fields].some((field) => {
        const currentValue = data[field] ?? "";
        const initialValue = initialData[field] ?? "";
        return currentValue !== initialValue;
    });
    const hasCollectionChanges =
        collections.size !== initialCollections.size ||
        [...collections].some((id) => !initialCollections.has(id));

    return hasCollectionDraft || hasFieldChanges || hasCollectionChanges;
}

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
