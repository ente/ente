import type { EnteFile } from "ente-media/file";

export interface SelectedState {
    [k: number]: boolean;
    count: number;
}
export type SetSelectedState = React.Dispatch<
    React.SetStateAction<SelectedState>
>;

export function getSelectedFiles(
    selected: SelectedState,
    files: EnteFile[],
): EnteFile[] {
    const selectedFilesIDs = new Set<number>();
    for (const [key, val] of Object.entries(selected)) {
        if (typeof val == "boolean" && val) {
            selectedFilesIDs.add(Number(key));
        }
    }

    return files.filter((file) => selectedFilesIDs.has(file.id));
}
