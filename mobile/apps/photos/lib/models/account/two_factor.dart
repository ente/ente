enum TwoFactorType { totp, passkey }

String twoFactorTypeToString(TwoFactorType type) {
  switch (type) {
    case TwoFactorType.totp:
      return "totp";
    case TwoFactorType.passkey:
      return "passkey";
  }
}
