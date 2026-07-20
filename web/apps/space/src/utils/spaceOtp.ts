export const spaceOTPCodeLength = 6;

export const sanitizeSpaceOTP = (value: string) =>
    value.replace(/\D/g, "").slice(0, spaceOTPCodeLength);
