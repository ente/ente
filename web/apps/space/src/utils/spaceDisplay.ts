export const firstNameFrom = (name: string) =>
    name.trim().split(/\s+/)[0] || name;

export const formatSpaceDate = (timestampMs: number): string => {
    const now = Date.now();
    const diff = now - timestampMs;
    const minutes = Math.floor(diff / 60000);
    if (minutes < 1) return "just now";
    if (minutes < 60) return `${minutes}m ago`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    if (days < 7) return `${days}d ago`;

    const date = new Date(timestampMs);
    const locale =
        typeof navigator == "undefined" ? "en-US" : navigator.language;
    if (date.getFullYear() == new Date(now).getFullYear()) {
        return date.toLocaleDateString(locale, {
            month: "short",
            day: "numeric",
        });
    }
    return date.toLocaleDateString(locale, {
        month: "short",
        day: "numeric",
        year: "numeric",
    });
};
