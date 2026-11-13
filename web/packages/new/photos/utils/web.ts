export const openURL = (url: string) => {
    const a = document.createElement("a");
    a.href = url;
    a.target = "_blank";
    a.rel = "noopener";
    a.click();
};

export const initiateEmail = (email: string) => {
    const a = document.createElement("a");
    a.href = "mailto:" + email;
    a.rel = "noopener";
    a.click();
};
