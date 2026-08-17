import zxcvbn from "zxcvbn";

export type PasswordStrength = "weak" | "moderate" | "strong";

export const estimatePasswordStrength = (
    password: string,
): PasswordStrength => {
    if (!password) {
        return "weak";
    }

    const zxcvbnResult = zxcvbn(password);
    if (zxcvbnResult.score < 2) {
        return "weak";
    } else if (zxcvbnResult.score < 3) {
        return "moderate";
    } else {
        return "strong";
    }
};

export const isWeakPassword = (password: string) =>
    estimatePasswordStrength(password) == "weak";
