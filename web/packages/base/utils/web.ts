export const saveAsFileAndRevokeObjectURL = (url: string, fileName: string) => {
    const a = document.createElement("a");
    a.style.display = "none";
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    URL.revokeObjectURL(url);
    a.remove();
};

export const saveStringAsFile = (s: string, fileName: string) => {
    const file = new Blob([s], { type: "text/plain" });
    const fileURL = URL.createObjectURL(file);
    saveAsFileAndRevokeObjectURL(fileURL, fileName);
};
