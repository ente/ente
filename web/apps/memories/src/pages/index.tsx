import dynamic from "next/dynamic";
import {
    PublicMemoryEmptyState,
    PublicMemoryErrorState,
    PublicMemoryLoadingContent,
    PublicMemoryLoadingState,
    PublicMemoryPageShell,
} from "../components/PublicMemoryPageShell";
import type {
    LaneMemoryViewerProps,
    MemoryViewerProps,
} from "../components/PublicMemoryViewerShared";
import { usePublicMemoryPage } from "../hooks/use-public-memory-page";

function ViewerChunkLoadingFallback() {
    return <PublicMemoryLoadingContent />;
}

const LaneMemoryViewer = dynamic<LaneMemoryViewerProps>(
    () =>
        import("../components/LaneMemoryViewer").then(
            (module) => module.LaneMemoryViewer,
        ),
    { loading: ViewerChunkLoadingFallback },
);

const MemoryViewer = dynamic<MemoryViewerProps>(
    () =>
        import("../components/MemoryViewer").then(
            (module) => module.MemoryViewer,
        ),
    { loading: ViewerChunkLoadingFallback },
);

// This single page serves every path: share links like /TOKEN#key reach it
// via the _redirects file (Cloudflare Pages), Next.js rewrites (dev), and
// nginx try_files (Docker), so do not add per-route pages.
export default function PublicMemoryPage() {
    const {
        currentIndex,
        errorMessage,
        files,
        goToNext,
        goToPrev,
        handleSeek,
        hideContent,
        laneFrames,
        loading,
        memoryMetadata,
        memoryName,
        viewerVariant,
    } = usePublicMemoryPage();

    if (hideContent) {
        return <PublicMemoryPageShell />;
    }

    if (loading) {
        return <PublicMemoryLoadingState />;
    }

    if (errorMessage) {
        return <PublicMemoryErrorState message={errorMessage} />;
    }

    if (!files || files.length === 0) {
        return <PublicMemoryEmptyState />;
    }

    const sharedViewerProps: MemoryViewerProps = {
        files,
        currentIndex,
        memoryName,
        onNext: goToNext,
        onPrev: goToPrev,
        onSeek: handleSeek,
    };

    const laneViewerProps: LaneMemoryViewerProps = {
        ...sharedViewerProps,
        memoryMetadata,
        laneFrames,
    };

    return (
        <PublicMemoryPageShell>
            {viewerVariant === "lane" ? (
                <LaneMemoryViewer {...laneViewerProps} />
            ) : (
                <MemoryViewer {...sharedViewerProps} />
            )}
        </PublicMemoryPageShell>
    );
}
