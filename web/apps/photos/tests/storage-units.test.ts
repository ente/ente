import { formattedStorageByteSize } from "ente-gallery/utils/units";
import { expect, test, vi } from "vitest";

vi.mock("i18next", () => ({
    t: (key: string) => key.replace("storage_unit.", "").toUpperCase(),
}));

test("TB usage retains precision alongside the quota and free space", () => {
    const gb = 1024 ** 3;
    const storage = 2 * 1024 ** 4;
    const usage = storage - 902 * gb;

    expect(formattedStorageByteSize(usage, { round: true })).toBe("1.1 TB");
    expect(formattedStorageByteSize(usage)).toBe("1.1 TB");
    expect(formattedStorageByteSize(storage)).toBe("2 TB");
    expect(formattedStorageByteSize(storage - usage)).toBe("902 GB");
    expect(formattedStorageByteSize(10.2 * gb, { round: true })).toBe("11 GB");
    expect(formattedStorageByteSize(10.2 * gb)).toBe("10 GB");
});
