import Foundation

enum AppEvent: Sendable {
  case ps5StateChanged(DeviceStatus)
  case ps5MonitoringReset
  case ps5ProbeFailed(count: Int)
  case displayChanged(DeviceStatus)
  case galaxyConnected
  case audioDeviceChanged
  case systemWillSleep
  case systemDidWake
}

extension Notification.Name {
  static let appEvent = Notification.Name("PersonalControlCenter.AppEvent")
}
