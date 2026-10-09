import Foundation

struct NotificationPayload: Decodable {
  let version: Int
  let eventType: String

  static func decrypt(_ ciphertext: String, recipient: NotificationRecipient) -> Self? {
    guard recipient.isValid, sodium_init() >= 0,
      let ciphertext = Data(base64Encoded: ciphertext), ciphertext.count >= 48,
      let publicKeyString = recipient.publicKey,
      let publicKey = Data(base64Encoded: publicKeyString),
      let privateKey = Data(base64Encoded: recipient.privateKey)
    else { return nil }
    var plaintext = [UInt8](repeating: 0, count: ciphertext.count - 48)
    guard crypto_box_seal_open(&plaintext, Array(ciphertext), UInt64(ciphertext.count),
      Array(publicKey), Array(privateKey)) == 0,
      let payload = try? JSONDecoder().decode(Self.self, from: Data(plaintext)),
      payload.version == 1
    else { return nil }
    return payload
  }
}
