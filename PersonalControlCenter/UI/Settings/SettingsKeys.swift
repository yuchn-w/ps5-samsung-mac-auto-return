import Foundation

enum SettingsKeys {
  static let showStatusText = "showStatusTextInMenuBar"
}

extension Notification.Name {
  static let statusTextPreferenceChanged = Notification.Name(
    "PersonalControlCenter.StatusTextPreferenceChanged")
}
