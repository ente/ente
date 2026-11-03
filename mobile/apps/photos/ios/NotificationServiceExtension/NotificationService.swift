import Foundation
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
  private let lock = NSLock()
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var fallback: UNNotificationContent?

  override func didReceive(_ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    guard request.content.userInfo["notificationCiphertext"] != nil,
      let content = request.content.mutableCopy() as? UNMutableNotificationContent
    else {
      contentHandler(request.content)
      return
    }
    content.title = "Ente"
    content.subtitle = ""
    content.body = "New activity"
    lock.lock()
    self.contentHandler = contentHandler
    fallback = content.copy() as? UNNotificationContent
    lock.unlock()

    if let ciphertext = request.content.userInfo["notificationCiphertext"] as? String,
      let recipient = try? NotificationKeyStore.read(),
      let event = NotificationEvent.decrypt(ciphertext, recipient: recipient),
      event.eventType == "album_shared" {
      content.body = "An album was shared with you"
    }
    finish(content)
  }

  override func serviceExtensionTimeWillExpire() {
    finish()
  }

  private func finish(_ content: UNNotificationContent? = nil) {
    lock.lock()
    let handler = contentHandler
    let result = content ?? fallback
    contentHandler = nil
    fallback = nil
    lock.unlock()
    if let handler, let result { handler(result) }
  }
}

private struct NotificationEvent: Decodable {
  let eventType: String

  static func decrypt(_ ciphertext: String, recipient: NotificationRecipient) -> Self? {
    guard recipient.isValid, ciphertext.utf8.count <= 4096,
      let ciphertext = Data(base64Encoded: ciphertext), ciphertext.count > 1136,
      let privateKey = Data(base64Encoded: recipient.privateKey)
    else { return nil }
    guard let plaintext = try? decryptNotification(ciphertext: ciphertext, privateKey: privateKey)
    else { return nil }
    return try? JSONDecoder().decode(Self.self, from: plaintext)
  }
}
