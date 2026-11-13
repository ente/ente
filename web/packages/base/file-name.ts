type FileNameComponents = [name: string, extension: string | undefined];

export const nameAndExtension = (fileName: string): FileNameComponents => {
    const i = fileName.lastIndexOf(".");
    if (i == -1) return [fileName, undefined];
    if (i == 0) return [fileName, undefined];
    return [fileName.slice(0, i), fileName.slice(i + 1)];
};

export const lowercaseExtension = (
    fileNameOrPath: string,
): string | undefined => {
    const [, ext] = nameAndExtension(fileNameOrPath);
    return ext?.toLowerCase();
};

export const fileNameFromComponents = (components: FileNameComponents) =>
    components.filter((x) => !!x).join(".");

export const basename = (path: string) => {
    const pathComponents = path.split("/");
    for (let i = pathComponents.length - 1; i >= 0; i--) {
        const component = pathComponents[i];
        if (component && component.length > 0) return component;
    }
    return path;
};

export const dirname = (path: string) => {
    const pathComponents = path.split("/");
    while (pathComponents.pop() == "") {
        // Drain trailing separators.
    }
    return pathComponents.join("/");
};

export const joinPath = (p1: string, p2: string) =>
    p1.endsWith("/") ? p1 + p2 : `${p1}/${p2}`;
