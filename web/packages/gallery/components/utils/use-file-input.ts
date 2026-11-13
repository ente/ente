import { useCallback, useEffect, useRef } from "react";

interface UseFileInputParams {
    directory?: boolean;
    accept?: string;
    onSelect: (selectedFiles: File[]) => void;
    onCancel: () => void;
}

interface UseFileInputResult {
    getInputProps: () => React.HTMLAttributes<HTMLInputElement>;
    openSelector: () => void;
}

export const useFileInput = ({
    directory,
    accept,
    onSelect,
    onCancel,
}: UseFileInputParams): UseFileInputResult => {
    const inputRef = useRef<HTMLInputElement | null>(null);

    useEffect(() => {
        // React 19 does not attach input cancellation through props.
        inputRef.current!.addEventListener("cancel", onCancel);
        return () => {
            inputRef.current?.removeEventListener("cancel", onCancel);
        };
    }, [onCancel]);

    const openSelector = useCallback(() => {
        inputRef.current!.value = "";
        inputRef.current!.click();
    }, []);

    const handleChange: React.ChangeEventHandler<HTMLInputElement> = (
        event,
    ) => {
        const files = event.target.files;
        if (files?.length) {
            onSelect([...files]);
        } else {
            onCancel();
        }
    };

    // Directory files expose POSIX paths through webkitRelativePath.
    const directoryOpts = directory
        ? { directory: "", webkitdirectory: "" }
        : {};

    const getInputProps = useCallback(
        () => ({
            type: "file",
            multiple: true,
            style: { display: "none" },
            ...directoryOpts,
            ref: inputRef,
            onChange: handleChange,
            ...(accept && { accept }),
        }),
        [directoryOpts, accept, handleChange],
    );

    return { getInputProps, openSelector };
};
