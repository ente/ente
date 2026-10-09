import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
  override func didReceive(_ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    guard request.content.userInfo["notificationVersion"] != nil else {
      contentHandler(request.content)
      return
    }
    guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
      contentHandler(request.content)
      return
    }
    content.title = "Ente Photos"
    content.subtitle = ""
    content.body = NSLocalizedString("notification.new_activity", value: "New activity", comment: "Generic notification fallback")
    let enabled = NotificationKeyStore.preferences.object(forKey: NotificationKeyStore.preferenceKey) as? Bool ?? false
    if enabled, request.content.userInfo["notificationVersion"] as? Int == 1,
      let ciphertext = request.content.userInfo["notificationCiphertext"] as? String,
      let recipient = try? NotificationKeyStore.read(),
      let payload = NotificationPayload.decrypt(ciphertext, recipient: recipient) {
      switch payload.eventType {
      case "album_shared":
        content.body = NSLocalizedString("notification.album_shared", value: "Someone shared an album with you", comment: "Album share notification")
      default:
        break
      }
    }
    contentHandler(content)
  }
}
