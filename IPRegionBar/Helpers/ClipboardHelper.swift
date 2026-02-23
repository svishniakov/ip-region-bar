import AppKit
import UserNotifications

enum ClipboardHelper {
    static func copyToPasteboard(_ value: String, fieldName: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        let content = UNMutableNotificationContent()
        content.title = "Copied"
        content.body = "\(fieldName): \(value)"

        let request = UNNotificationRequest(
            identifier: "copy-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
