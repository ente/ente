import { useCallback, useState } from "react";

export interface ModalVisibilityProps {
    open: boolean;
    onClose: () => void;
}

export const useModalVisibility = () => {
    const [open, setOpen] = useState(false);

    const show = useCallback(() => setOpen(true), []);
    const onClose = useCallback(() => setOpen(false), []);

    return { show, props: { open, onClose } };
};
