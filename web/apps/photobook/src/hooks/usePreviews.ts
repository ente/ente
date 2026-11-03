import { useBook } from "@/context/book";
import { useEffect, useRef } from "react";

export function usePreviews(photoIds: string[]) {
    const { retainPreviews } = useBook("retainPreviews");
    const releases = useRef(new Map<string, () => void>());
    useEffect(() => {
        const wanted = new Set(photoIds);
        for (const id of wanted) {
            if (!releases.current.has(id))
                releases.current.set(id, retainPreviews([id]));
        }
        for (const [id, release] of releases.current) {
            if (!wanted.has(id)) {
                release();
                releases.current.delete(id);
            }
        }
    }, [photoIds, retainPreviews]);
    useEffect(() => {
        const retained = releases.current;
        return () => {
            retained.forEach((release) => release());
            retained.clear();
        };
    }, []);
}
