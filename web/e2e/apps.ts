export const apps = {
    photos: { port: 3300, readyPath: "/signup" },
    locker: { port: 3309, readyPath: "/signup" },
    share: { port: 3305, readyPath: "/" },
} as const;

export const appServersFor = (projects: readonly string[]) =>
    projects.includes("share") && !projects.includes("locker")
        ? [...projects, "locker"]
        : projects;
