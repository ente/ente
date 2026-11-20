import MobileTextDialog from "@/components/MobileTextDialog";
import { useBook } from "@/context/book";
import { getSpineTitle } from "@/lib/printProducts";
import { useState } from "react";

export function useSpineTitlePrompt() {
    const { book, setBook } = useBook("book", "setBook");
    const spineTitle = getSpineTitle(book.title);
    const [pendingAction, setPendingAction] = useState<
        ((title: string) => void) | null
    >(null);

    const withSpineTitle = (action: (title: string) => void) => {
        if (spineTitle) action(spineTitle);
        else setPendingAction(() => action);
    };

    const spineTitleDialog = pendingAction && (
        <MobileTextDialog
            title="Add a spine title"
            description="Enter the title to print on the spine. For example, “Italy Trip 2026”, “Family Photos”, or “Our Wedding”."
            placeholder="Spine title"
            value=""
            actionLabel="Continue"
            isValid={(value) => Boolean(getSpineTitle(value))}
            onSave={(value) => {
                const title = getSpineTitle(value);
                setBook((previous) => ({ ...previous, title }));
                pendingAction(title);
            }}
            onClose={() => setPendingAction(null)}
        />
    );
    return { withSpineTitle, spineTitleDialog };
}
