import type { LockerItemType } from "@/types";

type LockerInfoInternalType = Exclude<LockerItemType, "file">;

const internalTypeByWireType = new Map<string, LockerInfoInternalType>([
    ["note", "note"],
    ["physical-record", "physicalRecord"],
    ["physicalRecord", "physicalRecord"],
    ["account-credential", "accountCredential"],
    ["accountCredential", "accountCredential"],
    ["emergency-contact", "emergencyContact"],
    ["emergencyContact", "emergencyContact"],
]);

export const fromInfoTypeWireValue = (
    value: string,
): LockerItemType | undefined => internalTypeByWireType.get(value);
