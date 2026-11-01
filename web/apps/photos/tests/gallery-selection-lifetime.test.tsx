import type { EnteFile } from "ente-media/file";
import { useState } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { expect, test } from "vitest";
import { emptySelection } from "../src/components/gallery/media/file-selection";
import { useGallerySelection } from "../src/components/gallery/media/use-gallery-selection";

const files = [
    { id: 1, ownerID: 1 },
    { id: 2, ownerID: 2 },
] as EnteFile[];
const both = { ...emptySelection, 1: true, 2: true, count: 2, ownCount: 1 };

test("finishing an older operation preserves a newer user selection", () => {
    let stage = 0;
    let finish: () => void;
    const Harness = () => {
        const selection = useGallerySelection(files, 1);
        if (stage === 0) {
            stage++;
            selection.setSelected(both);
        } else if (stage === 1) {
            stage++;
            finish = selection.clearSelection;
            selection.setSelected({
                ...emptySelection,
                2: true,
                count: 1,
                ownCount: 0,
            });
        } else if (stage === 2) {
            stage++;
            finish();
        }
        return (
            <span>
                {selection.selected.count}:
                {selection.selected[2] ? "second" : "none"}
            </span>
        );
    };
    expect(renderToStaticMarkup(<Harness />)).toBe("<span>1:second</span>");
});

test("finishing an operation still clears its selection after a data refresh", () => {
    let stage = 0;
    let finish: () => void;
    const Harness = () => {
        const [visible, setVisible] = useState(files);
        const selection = useGallerySelection(visible, 1);
        if (stage === 0) {
            stage++;
            selection.setSelected(both);
        } else if (stage === 1) {
            stage++;
            finish = selection.clearSelection;
            setVisible(files.slice(1));
        } else if (stage === 2) {
            stage++;
            expect(selection.selected.count).toBe(1);
            finish();
        }
        return <span>{selection.selected.count}</span>;
    };
    expect(renderToStaticMarkup(<Harness />)).toBe("<span>0</span>");
});
