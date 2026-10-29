import StartPage from "@/components/StartPage";
import { useBook } from "@/context/book";
import { useRouter } from "next/router";
import { useEffect } from "react";

export default function Home() {
    const router = useRouter();
    const { book, loading } = useBook();
    const hasBook = book.pages.length > 0;

    useEffect(() => {
        if (!loading && hasBook) void router.replace("/app");
    }, [loading, hasBook, router]);

    return loading || hasBook ? null : <StartPage />;
}
